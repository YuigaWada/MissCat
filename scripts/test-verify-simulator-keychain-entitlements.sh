#!/bin/bash

set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd)
verifier="$repository_root/scripts/verify-simulator-keychain-entitlements.sh"
fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT

fake_codesign="$fixture_root/codesign"
fake_otool="$fixture_root/otool"

cat >"$fake_codesign" <<'SCRIPT'
#!/bin/bash
bundle=${@: -1}
[[ -f "$bundle/signed-entitlements.plist" ]] || exit 1
cat "$bundle/signed-entitlements.plist"
SCRIPT
cat >"$fake_otool" <<'SCRIPT'
#!/bin/bash
executable=${@: -1}
metadata="$executable.section"
[[ -f "$metadata" ]] || exit 1
read -r offset size <"$metadata"
cat <<EOF
Section
  sectname __entitlements
   segname __TEXT
      size $size
    offset $offset
EOF
SCRIPT
chmod +x "$fake_codesign" "$fake_otool" "$verifier"

write_info() {
    local bundle=$1 executable=$2 access_group=$3
    mkdir -p "$bundle"
    cat >"$bundle/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$executable</string>
<key>MissCatKeychainAccessGroup</key><string>$access_group</string>
</dict></plist>
EOF
    : >"$bundle/$executable"
}

write_entitlements() {
    local path=$1 keychain_group=$2 application_group=$3
    cat >"$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>keychain-access-groups</key><array><string>$keychain_group</string></array>
<key>com.apple.security.application-groups</key><array><string>$application_group</string></array>
</dict></plist>
EOF
}

make_app() {
    local name=$1
    local app="$fixture_root/$name/MissCat.app"
    local share="$app/PlugIns/MissCatShare.appex"
    write_info "$app" MissCat "TEAM.yuwd.MissCat"
    write_info "$share" MissCatShare "TEAM.yuwd.MissCat"
    write_entitlements "$app/signed-entitlements.plist" "TEAM.yuwd.MissCat" "group.yuwd.MissCat"
    write_entitlements "$share/signed-entitlements.plist" "TEAM.yuwd.MissCat" "group.yuwd.MissCat"
    echo "$app"
}

run_verifier() {
    CODESIGN_BIN="$fake_codesign" OTOOL_BIN="$fake_otool" "$verifier" "$1" >/dev/null 2>&1
}

expect_success() {
    local name=$1 app=$2
    if ! run_verifier "$app"; then
        echo "FAIL: $name should succeed" >&2
        exit 1
    fi
}

expect_failure() {
    local name=$1 app=$2
    if run_verifier "$app"; then
        echo "FAIL: $name should fail" >&2
        exit 1
    fi
}

normal=$(make_app normal)
expect_success normal "$normal"

fallback=$(make_app fallback)
for bundle in "$fallback" "$fallback/PlugIns/MissCatShare.appex"; do
    plist="$bundle/signed-entitlements.plist"
    executable=$(/usr/bin/plutil -extract CFBundleExecutable raw "$bundle/Info.plist")
    size=$(wc -c <"$plist" | tr -d ' ')
    printf '0123456789abcdef' >"$bundle/$executable"
    cat "$plist" >>"$bundle/$executable"
    echo "16 $size" >"$bundle/$executable.section"
    rm "$plist"
done
expect_success fallback "$fallback"

unsigned=$(make_app unsigned)
rm "$unsigned/signed-entitlements.plist"
expect_failure unsigned "$unsigned"

mismatch=$(make_app mismatch)
write_entitlements "$mismatch/signed-entitlements.plist" "OTHER.yuwd.MissCat" "group.yuwd.MissCat"
expect_failure mismatch "$mismatch"

superstring=$(make_app superstring)
write_entitlements "$superstring/signed-entitlements.plist" "TEAM.yuwd.MissCat.attacker" "group.yuwd.MissCat"
expect_failure superstring "$superstring"

malformed=$(make_app malformed)
printf 'not a plist' >"$malformed/signed-entitlements.plist"
expect_failure malformed "$malformed"

disagreement=$(make_app disagreement)
/usr/bin/plutil -replace MissCatKeychainAccessGroup -string OTHER.yuwd.MissCat \
    "$disagreement/PlugIns/MissCatShare.appex/Info.plist"
expect_failure main-extension-disagreement "$disagreement"

echo "PASS: entitlement verifier fixtures"
