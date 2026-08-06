#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /path/to/MissCat.app" >&2
    exit 64
fi

app_path=$1
plutil_bin=${PLUTIL_BIN:-/usr/bin/plutil}
codesign_bin=${CODESIGN_BIN:-/usr/bin/codesign}
otool_bin=${OTOOL_BIN:-/usr/bin/otool}
dd_bin=${DD_BIN:-/bin/dd}
application_group="group.yuwd.MissCat"

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

fail() {
    echo "error: $1" >&2
    exit 78
}

plist_value() {
    local plist=$1
    local key=$2
    "$plutil_bin" -extract "$key" raw "$plist" 2>/dev/null
}

array_contains_exact_value() {
    local plist=$1
    local key=$2
    local expected=$3
    local count escaped_key
    escaped_key=${key//./\\.}
    count=$("$plutil_bin" -extract "$escaped_key" raw "$plist" 2>/dev/null) || return 1
    [[ "$count" =~ ^[0-9]+$ ]] || return 1

    local index value
    for ((index = 0; index < count; index++)); do
        value=$("$plutil_bin" -extract "$escaped_key.$index" raw "$plist" 2>/dev/null) || return 1
        [[ "$value" == "$expected" ]] && return 0
    done
    return 1
}

extract_entitlements() {
    local bundle_path=$1
    local destination=$2
    local info_plist="$bundle_path/Info.plist"
    local signed_output="$temporary_directory/$(basename "$bundle_path").signed.plist"
    local signed_diagnostics="$temporary_directory/$(basename "$bundle_path").codesign.log"

    if "$codesign_bin" -d --entitlements :- "$bundle_path" \
        >"$signed_output" 2>"$signed_diagnostics" \
        && "$plutil_bin" -lint "$signed_output" >/dev/null 2>&1 \
        && "$plutil_bin" -extract keychain-access-groups raw "$signed_output" >/dev/null 2>&1
    then
        cp "$signed_output" "$destination"
        return 0
    fi

    # Xcode 16 keeps Simulator-only entitlements in __TEXT,__entitlements.
    # `simctl install` consumes that section even when the ad-hoc signature has
    # no entitlement blob, so inspect the exact section as a fallback.
    local executable_name executable_path section_details section_offset section_size
    executable_name=$(plist_value "$info_plist" CFBundleExecutable) || return 1
    executable_path="$bundle_path/$executable_name"
    [[ -f "$executable_path" ]] || return 1
    section_details=$("$otool_bin" -l "$executable_path" 2>/dev/null) || return 1
    section_offset=$(awk '
        $1 == "sectname" && $2 == "__entitlements" { found = 1; next }
        found && $1 == "offset" { print $2; exit }
    ' <<< "$section_details")
    section_size=$(awk '
        $1 == "sectname" && $2 == "__entitlements" { found = 1; next }
        found && $1 == "size" { print $2; exit }
    ' <<< "$section_details")
    [[ -n "$section_offset" && -n "$section_size" ]] || return 1
    [[ "$section_offset" =~ ^(0x)?[0-9a-fA-F]+$ && "$section_size" =~ ^(0x)?[0-9a-fA-F]+$ ]] || return 1

    "$dd_bin" if="$executable_path" of="$destination" \
        bs=1 skip="$((section_offset))" count="$((section_size))" status=none 2>/dev/null || return 1
    "$plutil_bin" -lint "$destination" >/dev/null 2>&1 || return 1
    "$plutil_bin" -extract keychain-access-groups raw "$destination" >/dev/null 2>&1 || return 1
}

verify_bundle() {
    local bundle_path=$1
    local label=$2
    local expected_access_group=$3
    local entitlements_file="$temporary_directory/$label-entitlements.plist"

    extract_entitlements "$bundle_path" "$entitlements_file" || {
        fail "$label has no valid Simulator entitlement plist (build with code signing enabled)"
    }
    array_contains_exact_value "$entitlements_file" keychain-access-groups "$expected_access_group" || {
        fail "$label Keychain access group does not exactly match Info.plist"
    }
    array_contains_exact_value "$entitlements_file" com.apple.security.application-groups "$application_group" || {
        fail "$label has no exact $application_group application-group entitlement"
    }
}

main_info="$app_path/Info.plist"
share_path="$app_path/PlugIns/MissCatShare.appex"
share_info="$share_path/Info.plist"

[[ -d "$app_path" && -f "$main_info" ]] || {
    echo "error: MissCat app bundle was not found at $app_path" >&2
    exit 66
}
[[ -d "$share_path" && -f "$share_info" ]] || fail "embedded MissCatShare.appex was not found"

main_access_group=$(plist_value "$main_info" MissCatKeychainAccessGroup) || fail "main Info.plist has no Keychain access group"
share_access_group=$(plist_value "$share_info" MissCatKeychainAccessGroup) || fail "share Info.plist has no Keychain access group"
[[ -n "$main_access_group" && "$main_access_group" == "$share_access_group" ]] || {
    fail "main app and MissCatShare Info.plist Keychain access groups disagree"
}

verify_bundle "$app_path" main "$main_access_group"
verify_bundle "$share_path" share "$main_access_group"

echo "verified: main app and MissCatShare have exact matching Keychain and application-group entitlements"
