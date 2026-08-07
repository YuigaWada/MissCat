#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 1 ]]; then
    echo "usage: $0 [booted-simulator-udid]" >&2
    exit 64
fi

repository_root=$(cd "$(dirname "$0")/.." && pwd)
simulator_udid=${1:-$(xcrun simctl list devices booted -j \
    | plutil -extract devices json -o - - \
    | ruby -rjson -e 'puts JSON.parse(STDIN.read).values.flatten.first&.fetch("udid", "")')}

if [[ -z "$simulator_udid" ]]; then
    echo "error: boot a Simulator or pass its UDID" >&2
    exit 1
fi

evidence_root=$(mktemp -d "${TMPDIR:-/tmp}/MissCat-shared-keychain-e2e.XXXXXX")
app_derived_data="$evidence_root/AppDerivedData"
runner_derived_data="$evidence_root/RunnerDerivedData"
result_bundle="$evidence_root/SharedKeychainE2E.xcresult"
destination="platform=iOS Simulator,id=$simulator_udid"
app_bundle="$app_derived_data/Build/Products/Debug-iphonesimulator/MissCat.app"
xctestrun="$runner_derived_data/Build/Products/MissCatShareKeychainE2E_iphonesimulator18.5-arm64.xctestrun"

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

cd "$repository_root"
xcrun simctl bootstatus "$simulator_udid" -b

# Build the signed host independently. Associating it with the UI target makes
# XCTest reinstall a thinned copy whose Simulator Mach-O entitlement section
# is absent, so the detached runner must never list MissCat.app as a product.
xcodebuild \
    -quiet \
    -workspace MissCat.xcworkspace \
    -scheme MissCat \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$app_derived_data" \
    build \
    COMPILER_INDEX_STORE_ENABLE=NO

./scripts/verify-simulator-keychain-entitlements.sh "$app_bundle"

xcodebuild \
    -quiet \
    -workspace MissCat.xcworkspace \
    -scheme MissCatShareKeychainE2E \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$runner_derived_data" \
    build-for-testing \
    COMPILER_INDEX_STORE_ENABLE=NO

if [[ ! -f "$xctestrun" ]]; then
    xctestrun=$(find "$runner_derived_data/Build/Products" -maxdepth 1 \
        -name 'MissCatShareKeychainE2E_*.xctestrun' -print -quit)
fi
[[ -f "$xctestrun" ]] || {
    echo "error: detached UI-test xctestrun was not generated" >&2
    exit 1
}

xctestrun_dump="$evidence_root/xctestrun.txt"
plutil -p "$xctestrun" >"$xctestrun_dump"
if grep -Fq '__TESTROOT__/Debug-iphonesimulator/MissCat.app' "$xctestrun_dump"; then
    echo "error: UI-test plan would reinstall MissCat.app and invalidate the signed proof" >&2
    exit 1
fi

xcrun simctl uninstall "$simulator_udid" yuwd.MissCat >/dev/null 2>&1 || true
xcrun simctl install "$simulator_udid" "$app_bundle"

installed_app=$(xcrun simctl get_app_container "$simulator_udid" yuwd.MissCat app)
./scripts/verify-simulator-keychain-entitlements.sh "$installed_app"
xcrun simctl listapps "$simulator_udid" >"$evidence_root/listapps-after-test.plist"
/usr/libexec/PlistBuddy \
    -c 'Print :yuwd.MissCat:GroupContainers:group.yuwd.MissCat' \
    "$evidence_root/listapps-after-test.plist" >/dev/null

listapps_plist="$evidence_root/listapps-before-test.plist"
xcrun simctl listapps "$simulator_udid" >"$listapps_plist"
/usr/libexec/PlistBuddy \
    -c 'Print :yuwd.MissCat:GroupContainers:group.yuwd.MissCat' \
    "$listapps_plist" >/dev/null

xcodebuild \
    -quiet \
    -xctestrun "$xctestrun" \
    -destination "$destination" \
    -resultBundlePath "$result_bundle" \
    test-without-building \
    -only-testing:MissCatShareKeychainUITests \
    COMPILER_INDEX_STORE_ENABLE=NO

# A passing test is only meaningful if XCTest left the explicitly installed
# host intact; recheck both Mach-O entitlements after the real extension ran.
installed_app=$(xcrun simctl get_app_container "$simulator_udid" yuwd.MissCat app)
./scripts/verify-simulator-keychain-entitlements.sh "$installed_app"

echo "signed app-to-Share Keychain E2E passed"
echo "evidence: $result_bundle"
