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

if [[ "$entitlements" != *"keychain-access-groups"* ]]; then
    echo "error: app has no signed keychain-access-groups entitlement" >&2
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
