#!/bin/bash

set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd)
verifier="$repository_root/scripts/verify-simulator-keychain-entitlements.sh"
fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT

fake_codesign="$fixture_root/codesign"
fake_otool="$fixture_root/otool"
fake_lipo="$fixture_root/lipo"

cat >"$fake_codesign" <<'SCRIPT'
#!/bin/bash
bundle=${@: -1}
architecture=""
while (($#)); do
    if [[ "$1" == "--arch" ]]; then
        architecture=$2
        shift 2
        continue
    fi
    shift
done
per_architecture="$bundle/signed-entitlements-$architecture.plist"
fallback="$bundle/signed-entitlements.plist"
if [[ -n "$architecture" && -f "$per_architecture" ]]; then
    cat "$per_architecture"
elif [[ -f "$fallback" ]]; then
    cat "$fallback"
else
    exit 1
fi
SCRIPT
cat >"$fake_lipo" <<'SCRIPT'
#!/bin/bash
if [[ "$1" == "-archs" ]]; then
    echo arm64
    exit 0
fi
exit 1
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
chmod +x "$fake_codesign" "$fake_otool" "$fake_lipo" "$verifier"

write_info() {
    local bundle=$1 executable=$2 access_group=$3
    mkdir -p "$bundle"
    cat >"$bundle/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$executable</string>
<key>MissCatSecureStoreAccessGroup</key><string>$access_group</string>
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
    CODESIGN_BIN="$fake_codesign" OTOOL_BIN="$fake_otool" LIPO_BIN="$fake_lipo" \
        "$verifier" "$1" >/dev/null 2>&1
}

run_real_fat_verifier() {
    CODESIGN_BIN="$fake_codesign" OTOOL_BIN=/usr/bin/otool LIPO_BIN=/usr/bin/lipo \
        "$verifier" "$1" >/dev/null 2>&1
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

expect_real_fat_success() {
    local name=$1 app=$2
    if ! run_real_fat_verifier "$app"; then
        echo "FAIL: $name should succeed" >&2
        exit 1
    fi
}

expect_real_fat_failure() {
    local name=$1 app=$2
    if run_real_fat_verifier "$app"; then
        echo "FAIL: $name should fail" >&2
        exit 1
    fi
}

printf 'int main(void) { return 0; }\n' >"$fixture_root/main.c"

make_macho_slice() {
    local architecture=$1 entitlements=$2 destination=$3
    if [[ "$entitlements" == "none" ]]; then
        xcrun --sdk iphonesimulator clang \
            -target "$architecture-apple-ios17.0-simulator" \
            "$fixture_root/main.c" -o "$destination"
    else
        xcrun --sdk iphonesimulator clang \
            -target "$architecture-apple-ios17.0-simulator" \
            "$fixture_root/main.c" \
            -Wl,-sectcreate,__TEXT,__entitlements,"$entitlements" \
            -o "$destination"
    fi
}

make_fat_executable() {
    local destination=$1 arm_entitlements=$2 x86_entitlements=$3
    local arm_slice="$destination.arm64"
    local x86_slice="$destination.x86_64"
    make_macho_slice arm64 "$arm_entitlements" "$arm_slice"
    make_macho_slice x86_64 "$x86_entitlements" "$x86_slice"
    /usr/bin/lipo -create "$arm_slice" "$x86_slice" -output "$destination"
}

make_real_fat_app() {
    local name=$1 main_x86_entitlements=$2 share_x86_entitlements=$3
    local app
    app=$(make_app "$name")
    local share="$app/PlugIns/MissCatShare.appex"
    local main_valid="$app/signed-entitlements.plist"
    local share_valid="$share/signed-entitlements.plist"
    make_fat_executable "$app/MissCat" "$main_valid" "$main_x86_entitlements"
    make_fat_executable "$share/MissCatShare" "$share_valid" "$share_x86_entitlements"
    rm "$main_valid" "$share_valid"
    echo "$app"
}

make_signed_real_fat_app() {
    local name=$1
    local app
    app=$(make_app "$name")
    local share="$app/PlugIns/MissCatShare.appex"
    local bundle executable signed
    for bundle in "$app" "$share"; do
        executable=$(/usr/bin/plutil -extract CFBundleExecutable raw "$bundle/Info.plist")
        signed="$bundle/signed-entitlements.plist"
        cp "$signed" "$bundle/signed-entitlements-arm64.plist"
        cp "$signed" "$bundle/signed-entitlements-x86_64.plist"
        rm "$signed"
        make_fat_executable "$bundle/$executable" none none
    done
    echo "$app"
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

truncated=$(make_app truncated)
truncated_bundle="$truncated/PlugIns/MissCatShare.appex"
truncated_plist="$truncated_bundle/signed-entitlements.plist"
truncated_executable=$(/usr/bin/plutil -extract CFBundleExecutable raw "$truncated_bundle/Info.plist")
truncated_size=$(wc -c <"$truncated_plist" | tr -d ' ')
printf '0123456789abcdef' >"$truncated_bundle/$truncated_executable"
cat "$truncated_plist" >>"$truncated_bundle/$truncated_executable"
echo "16 $((truncated_size + 32))" >"$truncated_bundle/$truncated_executable.section"
rm "$truncated_plist"
expect_failure truncated-macho-fallback "$truncated"

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
/usr/bin/plutil -replace MissCatSecureStoreAccessGroup -string OTHER.yuwd.MissCat \
    "$disagreement/PlugIns/MissCatShare.appex/Info.plist"
expect_failure main-extension-disagreement "$disagreement"

wrong_share=$(make_app wrong-share)
write_entitlements \
    "$wrong_share/PlugIns/MissCatShare.appex/signed-entitlements.plist" \
    "OTHER.yuwd.MissCat" \
    "group.yuwd.MissCat"
expect_failure wrong-share-entitlement-with-matching-info "$wrong_share"

extra_group=$(make_app extra-group)
/usr/bin/plutil -insert keychain-access-groups.1 -string OTHER.yuwd.MissCat \
    "$extra_group/signed-entitlements.plist"
expect_failure extra-keychain-group "$extra_group"

real_fat_valid_template=$(make_app real-fat-valid-template)
valid_entitlements="$real_fat_valid_template/signed-entitlements.plist"
valid_share_entitlements="$real_fat_valid_template/PlugIns/MissCatShare.appex/signed-entitlements.plist"

fat_valid=$(make_real_fat_app real-fat-valid "$valid_entitlements" "$valid_share_entitlements")
expect_real_fat_success real-fat-all-slices-valid "$fat_valid"

invalid_slice_entitlements="$fixture_root/invalid-slice-entitlements.plist"
write_entitlements "$invalid_slice_entitlements" "OTHER.yuwd.MissCat" "group.yuwd.MissCat"
fat_divergent=$(make_real_fat_app \
    real-fat-divergent "$valid_entitlements" "$invalid_slice_entitlements")
expect_real_fat_failure real-fat-one-valid-one-invalid-slice "$fat_divergent"

fat_missing=$(make_real_fat_app real-fat-missing "$valid_entitlements" none)
expect_real_fat_failure real-fat-missing-entitlements-section "$fat_missing"

malformed_slice_entitlements="$fixture_root/malformed-slice-entitlements.plist"
printf 'not a plist' >"$malformed_slice_entitlements"
fat_malformed=$(make_real_fat_app \
    real-fat-malformed "$valid_entitlements" "$malformed_slice_entitlements")
expect_real_fat_failure real-fat-malformed-entitlements-section "$fat_malformed"

signed_fat=$(make_signed_real_fat_app signed-real-fat)
expect_real_fat_success signed-real-fat-all-slices-valid "$signed_fat"

signed_fat_divergent=$(make_signed_real_fat_app signed-real-fat-divergent)
/usr/bin/plutil -insert slice-marker -string x86_64 \
    "$signed_fat_divergent/PlugIns/MissCatShare.appex/signed-entitlements-x86_64.plist"
expect_real_fat_failure signed-real-fat-slice-payload-disagreement "$signed_fat_divergent"

signed_fat_malformed=$(make_signed_real_fat_app signed-real-fat-malformed)
printf 'not a plist' \
    >"$signed_fat_malformed/PlugIns/MissCatShare.appex/signed-entitlements-x86_64.plist"
expect_real_fat_failure signed-real-fat-malformed-slice "$signed_fat_malformed"

echo "PASS: entitlement verifier fixtures"
