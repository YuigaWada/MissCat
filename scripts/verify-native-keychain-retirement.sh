#!/bin/bash

set -euo pipefail

repository_root=${REPOSITORY_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
app_bundle=${1:-}
forbidden_dependency="Keychain""Access"
rg_bin=${RG_BIN:-$(command -v rg)}
otool_bin=${OTOOL_BIN:-/usr/bin/otool}
plutil_bin=${PLUTIL_BIN:-/usr/bin/plutil}

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

scan_roots=(
    Podfile
    Podfile.lock
    Pods/Manifest.lock
    Pods/Pods.xcodeproj
    "Pods/Target Support Files"
    MissCat.xcodeproj
    MissCat.xcworkspace
    MissCat
    MissCatShare
    MissCatTests
    config
    docs
    scripts
)

existing_roots=()
for relative_path in "${scan_roots[@]}"; do
    path="$repository_root/$relative_path"
    [[ -e "$path" ]] && existing_roots+=("$path")
done

if ((${#existing_roots[@]})) && \
    "$rg_bin" --hidden --fixed-strings --files-with-matches \
        --glob '!.git/**' "$forbidden_dependency" "${existing_roots[@]}" >/dev/null; then
    fail "retired dependency name remains in source or integration metadata"
fi

for relative_path in Pods MissCat.xcodeproj MissCat.xcworkspace MissCat MissCatShare; do
    path="$repository_root/$relative_path"
    [[ -e "$path" ]] || continue
    if /usr/bin/find "$path" -iname "*$forbidden_dependency*" -print -quit | /usr/bin/grep -q .; then
        fail "retired dependency target or artifact remains under $relative_path"
    fi
done

if [[ -z "$app_bundle" ]]; then
    echo "Native keychain retirement static gate passed."
    exit 0
fi

[[ -d "$app_bundle" ]] || fail "app bundle was not found: $app_bundle"

if /usr/bin/find "$app_bundle" -iname "*$forbidden_dependency*" -print -quit | /usr/bin/grep -q .; then
    fail "retired dependency framework or named artifact is embedded in the app"
fi

if "$rg_bin" --text --fixed-strings --files-with-matches \
    "$forbidden_dependency" "$app_bundle" >/dev/null; then
    fail "retired dependency string is present in the app bundle"
fi

bundles=("$app_bundle")
while IFS= read -r extension_bundle; do
    bundles+=("$extension_bundle")
done < <(/usr/bin/find "$app_bundle" -type d -name '*.appex' -print)

for bundle in "${bundles[@]}"; do
    info_plist="$bundle/Info.plist"
    [[ -f "$info_plist" ]] || fail "bundle has no Info.plist: $bundle"
    executable_name=$(
        "$plutil_bin" -extract CFBundleExecutable raw -o - "$info_plist" 2>/dev/null
    ) || fail "bundle has no CFBundleExecutable: $bundle"
    executable="$bundle/$executable_name"
    [[ -f "$executable" ]] || fail "bundle executable was not found: $executable"
    if "$otool_bin" -L "$executable" | /usr/bin/grep -Fq "$forbidden_dependency"; then
        fail "retired dependency remains in LC_LOAD_DYLIB: $executable"
    fi
done

echo "Native keychain retirement bundle gate passed for ${#bundles[@]} executable(s)."
