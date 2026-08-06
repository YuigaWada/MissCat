#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly compare_script="$script_dir/compare-screenshots.sh"
readonly magick_bin="${MAGICK_BIN:-/opt/homebrew/bin/magick}"

fail() {
    printf 'self-test failed: %s\n' "$*" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

file_sha() {
    /usr/bin/openssl dgst -sha256 -r "$1" | awk '{ print $1 }'
}

assert_json_contains() {
    local json_path="$1"
    local expected="$2"
    /usr/bin/grep -Fq "$expected" "$json_path" || fail "$json_path does not contain: $expected"
}

[[ -x "$magick_bin" ]] || fail "ImageMagick is unavailable: $magick_bin"
[[ -x "$compare_script" ]] || fail "comparison script is not executable: $compare_script"

fixture_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/misscat visual diff test.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT

baseline="$fixture_dir/baseline image.png"
identical="$fixture_dir/identical candidate.png"
changed="$fixture_dir/changed candidate.png"
near_color="$fixture_dir/near color candidate.png"
wrong_size="$fixture_dir/wrong size candidate.png"
mask="$fixture_dir/status mask.png"

"$magick_bin" -size 4x4 xc:white "$baseline"
"$magick_bin" "$baseline" "$identical"
"$magick_bin" "$baseline" -fill black -draw 'point 1,1' "$changed"
"$magick_bin" -size 4x4 xc:'#fefefe' "$near_color"
"$magick_bin" -size 3x4 xc:white "$wrong_size"
"$magick_bin" -size 4x4 xc:white -fill black -draw 'point 1,1' "$mask"

identical_out="$fixture_dir/identical output"
"$compare_script" --magick "$magick_bin" --out "$identical_out" "$baseline" "$identical"
/usr/bin/plutil -convert json -o /dev/null -- "$identical_out/summary.json"
assert_json_contains "$identical_out/summary.json" '"status": "passed"'
assert_json_contains "$identical_out/summary.json" '"changed_pixels": 0'
assert_file "$identical_out/diff-heatmap.png"
assert_file "$identical_out/side-by-side.png"
assert_file "$identical_out/overlay.png"
summary_sha=$(file_sha "$identical_out/summary.json")
heatmap_sha=$(file_sha "$identical_out/diff-heatmap.png")
side_by_side_sha=$(file_sha "$identical_out/side-by-side.png")
overlay_sha=$(file_sha "$identical_out/overlay.png")
"$compare_script" --magick "$magick_bin" --out "$identical_out" "$baseline" "$identical" >/dev/null
[[ "$(file_sha "$identical_out/summary.json")" == "$summary_sha" ]] || fail "summary is not deterministic"
[[ "$(file_sha "$identical_out/diff-heatmap.png")" == "$heatmap_sha" ]] || fail "heatmap is not deterministic"
[[ "$(file_sha "$identical_out/side-by-side.png")" == "$side_by_side_sha" ]] || fail "side-by-side image is not deterministic"
[[ "$(file_sha "$identical_out/overlay.png")" == "$overlay_sha" ]] || fail "overlay image is not deterministic"

changed_out="$fixture_dir/changed output"
changed_status=0
"$compare_script" --magick "$magick_bin" --out "$changed_out" "$baseline" "$changed" || changed_status=$?
[[ "$changed_status" -eq 1 ]] || fail "changed image should exceed the zero threshold"
assert_json_contains "$changed_out/summary.json" '"status": "threshold_exceeded"'
assert_json_contains "$changed_out/summary.json" '"changed_pixels": 1'
assert_json_contains "$changed_out/summary.json" '"changed_ratio": 0.0625'

allowed_out="$fixture_dir/allowed output"
"$compare_script" --magick "$magick_bin" --threshold 0.0625 --out "$allowed_out" "$baseline" "$changed"
assert_json_contains "$allowed_out/summary.json" '"status": "passed"'

rmse_out="$fixture_dir/rmse output"
rmse_status=0
"$compare_script" --magick "$magick_bin" --threshold 1 --max-rmse 0.1 \
    --out "$rmse_out" "$baseline" "$changed" || rmse_status=$?
[[ "$rmse_status" -eq 1 ]] || fail "changed image should exceed the RMSE threshold"
assert_json_contains "$rmse_out/summary.json" '"normalized_rmse_exceeded": true'

fuzz_out="$fixture_dir/fuzz output"
"$compare_script" --magick "$magick_bin" --fuzz 1% --out "$fuzz_out" "$baseline" "$near_color"
assert_json_contains "$fuzz_out/summary.json" '"changed_pixels": 0'

masked_out="$fixture_dir/masked output"
"$compare_script" --magick "$magick_bin" --mask "$mask" --out "$masked_out" "$baseline" "$changed"
assert_json_contains "$masked_out/summary.json" '"applied": true'
assert_json_contains "$masked_out/summary.json" '"ignored_pixels": 1'
assert_json_contains "$masked_out/summary.json" '"changed_pixels": 0'

dimension_out="$fixture_dir/dimension output"
dimension_status=0
"$compare_script" --magick "$magick_bin" --out "$dimension_out" "$baseline" "$wrong_size" \
    >/dev/null 2>&1 || dimension_status=$?
[[ "$dimension_status" -eq 2 ]] || fail "dimension mismatch should exit 2"
/usr/bin/plutil -convert json -o /dev/null -- "$dimension_out/summary.json"
assert_json_contains "$dimension_out/summary.json" '"status": "dimension_mismatch"'

printf 'visual diff self-test passed (%s)\n' "$fixture_dir"
