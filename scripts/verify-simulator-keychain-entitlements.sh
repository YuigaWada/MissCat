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
lipo_bin=${LIPO_BIN:-/usr/bin/lipo}
dd_bin=${DD_BIN:-/bin/dd}
wc_bin=${WC_BIN:-/usr/bin/wc}
cmp_bin=${CMP_BIN:-/usr/bin/cmp}
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

array_equals_single_value() {
    local plist=$1
    local key=$2
    local expected=$3
    local count escaped_key
    escaped_key=${key//./\\.}
    count=$("$plutil_bin" -extract "$escaped_key" raw "$plist" 2>/dev/null) || return 1
    [[ "$count" =~ ^[0-9]+$ ]] || return 1

    [[ "$count" == 1 ]] || return 1
    local value
    value=$("$plutil_bin" -extract "$escaped_key.0" raw "$plist" 2>/dev/null) || return 1
    [[ "$value" == "$expected" ]]
}

extract_signed_entitlements() {
    local bundle_path=$1
    local architecture=$2
    local destination=$3
    local signed_output="$temporary_directory/$(basename "$bundle_path").$architecture.signed.plist"
    local signed_diagnostics="$temporary_directory/$(basename "$bundle_path").$architecture.codesign.log"

    if "$codesign_bin" -d --arch "$architecture" --entitlements :- "$bundle_path" \
        >"$signed_output" 2>"$signed_diagnostics"
    then
        # An empty or valid keychain-less plist is how Xcode 16 represents an
        # ad-hoc Simulator signature whose entitlements live in the Mach-O
        # section. A malformed non-empty signed payload is authoritative bad
        # data and must never be hidden by the section fallback.
        [[ -s "$signed_output" ]] || return 1
        "$plutil_bin" -lint "$signed_output" >/dev/null 2>&1 || return 2
        "$plutil_bin" -extract keychain-access-groups raw "$signed_output" >/dev/null 2>&1 || return 1
        cp "$signed_output" "$destination"
        return 0
    fi
    return 1
}

extract_section_entitlements() {
    local executable_path=$1
    local architecture=$2
    local architecture_count=$3
    local destination=$4
    local slice_path=$executable_path

    if ((architecture_count > 1)); then
        slice_path="$temporary_directory/$(basename "$executable_path").$architecture.slice"
        "$lipo_bin" -thin "$architecture" "$executable_path" -output "$slice_path" \
            >/dev/null 2>&1 || return 1
    fi

    # Xcode 16 keeps Simulator-only entitlements in __TEXT,__entitlements.
    # `simctl install` consumes that section even when the ad-hoc signature has
    # no entitlement blob. Inspect a separately thinned file so offsets can
    # never be confused with the universal Mach-O container's offsets.
    local section_details section_offset section_size
    local section_offset_decimal section_size_decimal section_end executable_size extracted_size
    section_details=$("$otool_bin" -l "$slice_path" 2>/dev/null) || return 1
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

    if [[ "$section_offset" == 0x* || "$section_offset" == 0X* ]]; then
        section_offset_decimal=$((section_offset))
    else
        section_offset_decimal=$((10#$section_offset))
    fi
    if [[ "$section_size" == 0x* || "$section_size" == 0X* ]]; then
        section_size_decimal=$((section_size))
    else
        section_size_decimal=$((10#$section_size))
    fi
    section_end=$((section_offset_decimal + section_size_decimal))
    executable_size=$("$wc_bin" -c <"$slice_path" | tr -d '[:space:]') || return 1
    [[ "$executable_size" =~ ^[0-9]+$ ]] || return 1
    ((section_offset_decimal >= 0 && section_size_decimal > 0)) || return 1
    ((section_end >= section_offset_decimal && section_end <= executable_size)) || return 1

    "$dd_bin" if="$slice_path" of="$destination" \
        bs=1 skip="$section_offset_decimal" count="$section_size_decimal" status=none 2>/dev/null || return 1
    extracted_size=$("$wc_bin" -c <"$destination" | tr -d '[:space:]') || return 1
    [[ "$extracted_size" == "$section_size_decimal" ]] || return 1
    "$plutil_bin" -lint "$destination" >/dev/null 2>&1 || return 1
    "$plutil_bin" -extract keychain-access-groups raw "$destination" >/dev/null 2>&1 || return 1
}

verify_bundle() {
    local bundle_path=$1
    local label=$2
    local expected_access_group=$3
    local info_plist="$bundle_path/Info.plist"
    local executable_name executable_path architecture_output
    executable_name=$(plist_value "$info_plist" CFBundleExecutable) || {
        fail "$label Info.plist has no executable"
    }
    executable_path="$bundle_path/$executable_name"
    [[ -f "$executable_path" ]] || fail "$label executable was not found"

    architecture_output=$("$lipo_bin" -archs "$executable_path" 2>/dev/null) || {
        fail "$label executable has no readable Mach-O architectures"
    }
    local -a architectures
    read -r -a architectures <<<"$architecture_output"
    ((${#architectures[@]} > 0)) || fail "$label executable has no Mach-O architectures"

    local architecture entitlements_file normalized_file canonical_file signed_status
    canonical_file="$temporary_directory/$label.canonical-entitlements.plist"
    for architecture in "${architectures[@]}"; do
        [[ "$architecture" =~ ^[A-Za-z0-9_]+$ ]] || fail "$label has an invalid architecture name"
        entitlements_file="$temporary_directory/$label.$architecture.entitlements.plist"

        if extract_signed_entitlements "$bundle_path" "$architecture" "$entitlements_file"; then
            : # A valid signed payload is authoritative for this architecture.
        else
            signed_status=$?
            [[ "$signed_status" != 2 ]] || fail "$label $architecture has malformed signed entitlements"
            extract_section_entitlements \
                "$executable_path" "$architecture" "${#architectures[@]}" "$entitlements_file" || {
                fail "$label $architecture has no valid Simulator entitlement plist (build with code signing enabled)"
            }
        fi

        array_equals_single_value "$entitlements_file" keychain-access-groups "$expected_access_group" || {
            fail "$label $architecture Keychain access group does not exactly match Info.plist"
        }
        array_equals_single_value "$entitlements_file" com.apple.security.application-groups "$application_group" || {
            fail "$label $architecture has no exact $application_group application-group entitlement"
        }

        normalized_file="$temporary_directory/$label.$architecture.normalized-entitlements.plist"
        "$plutil_bin" -convert binary1 -o "$normalized_file" "$entitlements_file" >/dev/null 2>&1 || {
            fail "$label $architecture entitlements could not be normalized"
        }
        if [[ -f "$canonical_file" ]]; then
            "$cmp_bin" -s "$canonical_file" "$normalized_file" || {
                fail "$label entitlement payloads disagree between architecture slices"
            }
        else
            cp "$normalized_file" "$canonical_file"
        fi
    done
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

echo "verified: every main app and MissCatShare architecture has exact matching Keychain and application-group entitlements"
