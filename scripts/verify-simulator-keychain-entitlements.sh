#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /path/to/MissCat.app" >&2
    exit 64
fi

app_path=$1
info_plist="$app_path/Info.plist"

if [[ ! -d "$app_path" || ! -f "$info_plist" ]]; then
    echo "error: MissCat app bundle was not found at $app_path" >&2
    exit 66
fi

expected_access_group=$(/usr/bin/plutil -extract MissCatKeychainAccessGroup raw "$info_plist")
if [[ -z "$expected_access_group" ]]; then
    echo "error: MissCatKeychainAccessGroup is empty" >&2
    exit 65
fi

entitlements=$(/usr/bin/codesign -d --entitlements :- "$app_path" 2>&1 || true)

# Xcode 16 keeps Simulator-only entitlements in the executable's
# __TEXT,__entitlements section instead of the normal code-signature blob.
# `simctl install` needs that section, so inspect it when codesign reports an
# empty entitlement dictionary.
if [[ "$entitlements" != *"keychain-access-groups"* ]]; then
    executable_name=$(/usr/bin/plutil -extract CFBundleExecutable raw "$info_plist")
    executable_path="$app_path/$executable_name"
    section_details=$(/usr/bin/otool -l "$executable_path")
    section_offset=$(awk '
        $1 == "sectname" && $2 == "__entitlements" { found = 1; next }
        found && $1 == "offset" { print $2; exit }
    ' <<< "$section_details")
    section_size=$(awk '
        $1 == "sectname" && $2 == "__entitlements" { found = 1; next }
        found && $1 == "size" { print $2; exit }
    ' <<< "$section_details")

    if [[ -n "$section_offset" && -n "$section_size" ]]; then
        entitlements_file=$(mktemp)
        trap 'rm -f "$entitlements_file"' EXIT
        /bin/dd if="$executable_path" of="$entitlements_file" \
            bs=1 skip="$section_offset" count="$((section_size))" status=none
        entitlements=$(/usr/bin/plutil -convert xml1 -o - "$entitlements_file" 2>/dev/null || true)
    fi
fi

if [[ "$entitlements" != *"keychain-access-groups"* ]]; then
    echo "error: app has no Simulator keychain-access-groups entitlement" >&2
    echo "Build Simulator previews with code signing enabled; do not use CODE_SIGNING_ALLOWED=NO." >&2
    exit 78
fi

if [[ "$entitlements" != *"$expected_access_group"* ]]; then
    echo "error: signed Keychain access group does not match Info.plist" >&2
    echo "Expected: $expected_access_group" >&2
    exit 78
fi

if [[ "$entitlements" != *"group.yuwd.MissCat"* ]]; then
    echo "error: app has no signed MissCat application-group entitlement" >&2
    exit 78
fi

echo "verified: signed Simulator app contains the configured Keychain and application groups"
