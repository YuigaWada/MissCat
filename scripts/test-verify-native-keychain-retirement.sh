#!/bin/bash

set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd)
verifier="$repository_root/scripts/verify-native-keychain-retirement.sh"
fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT

forbidden_dependency="Keychain""Access"
fixture_repository="$fixture_root/repository"
app_bundle="$fixture_root/MissCat.app"
fake_otool="$fixture_root/otool"

mkdir -p "$fixture_repository/scripts" "$app_bundle/Frameworks"
: >"$fixture_repository/Podfile"
: >"$fixture_repository/Podfile.lock"

cat >"$app_bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MissCat</string>
</dict>
</plist>
PLIST
: >"$app_bundle/MissCat"

cat >"$fake_otool" <<'SCRIPT'
#!/bin/bash
echo "$2:"
echo "    /usr/lib/libSystem.B.dylib"
if [[ "${INJECT_FORBIDDEN_LOAD:-0}" == 1 ]]; then
    echo "    @rpath/${FORBIDDEN_DEPENDENCY_NAME}.framework/${FORBIDDEN_DEPENDENCY_NAME}"
fi
SCRIPT
chmod +x "$fake_otool" "$verifier"

run_verifier() {
    REPOSITORY_ROOT="$fixture_repository" OTOOL_BIN="$fake_otool" \
        "$verifier" "$app_bundle" >/dev/null 2>&1
}

expect_failure() {
    local label=$1
    if run_verifier; then
        echo "FAIL: $label should be rejected" >&2
        exit 1
    fi
}

run_verifier

printf "pod '%s'\n" "$forbidden_dependency" >"$fixture_repository/Podfile"
expect_failure source-reference
: >"$fixture_repository/Podfile"

mkdir "$app_bundle/Frameworks/$forbidden_dependency.framework"
expect_failure embedded-framework
rmdir "$app_bundle/Frameworks/$forbidden_dependency.framework"

printf '%s\n' "$forbidden_dependency" >"$app_bundle/retired-dependency.txt"
expect_failure bundled-string
rm "$app_bundle/retired-dependency.txt"

if INJECT_FORBIDDEN_LOAD=1 FORBIDDEN_DEPENDENCY_NAME="$forbidden_dependency" \
    REPOSITORY_ROOT="$fixture_repository" OTOOL_BIN="$fake_otool" \
    "$verifier" "$app_bundle" >/dev/null 2>&1; then
    echo "FAIL: LC_LOAD_DYLIB reference should be rejected" >&2
    exit 1
fi

echo "Native keychain retirement verifier positive and negative tests passed."
