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

assert_json_integer() {
    local json_path="$1"
    local key_path="$2"
    local expected="$3"
    local actual
    actual=$(/usr/bin/plutil -extract "$key_path" raw -expect integer -- "$json_path") || \
        fail "$json_path does not contain integer $key_path"
    [[ "$actual" == "$expected" ]] || \
        fail "$json_path has $key_path=$actual, expected $expected"
}

[[ -x "$magick_bin" ]] || fail "ImageMagick is unavailable: $magick_bin"
[[ -x "$compare_script" ]] || fail "comparison script is not executable: $compare_script"

fixture_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/misscat visual diff test.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT
metadata_args=(
    --surface-id 01
    --state comparator-selftest
    --appearance light
    --device fixture-device
    --orientation portrait
    --fixture comparator-selftest
    --locale ja-jp
    --content-size medium
    --visual-ready visual-ready.comparator-selftest
    --record-relative-to "$fixture_dir"
)

baseline="$fixture_dir/baseline image.png"
identical="$fixture_dir/identical candidate.png"
changed="$fixture_dir/changed candidate.png"
near_color="$fixture_dir/near color candidate.png"
beyond_tolerance="$fixture_dir/beyond tolerance candidate.png"
wrong_size="$fixture_dir/wrong size candidate.png"
mask="$fixture_dir/status mask.png"

"$magick_bin" -size 4x4 xc:white "$baseline"
"$magick_bin" "$baseline" "$identical"
"$magick_bin" "$baseline" -fill black -draw 'point 1,1' "$changed"
"$magick_bin" -size 4x4 xc:'#f7f7f7' "$near_color"
"$magick_bin" -size 4x4 xc:'#f6f6f6' "$beyond_tolerance"
"$magick_bin" -size 3x4 xc:white "$wrong_size"
"$magick_bin" -size 4x4 xc:white -fill black -draw 'point 1,1' "$mask"

identical_out="$fixture_dir/identical output"
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --out "$identical_out" "$baseline" "$identical"
/usr/bin/plutil -convert json -o /dev/null -- "$identical_out/summary.json"
assert_json_contains "$identical_out/summary.json" '"status": "passed"'
assert_json_contains "$identical_out/summary.json" '"changed_pixels": 0'
assert_json_contains "$identical_out/summary.json" '"changed_similarity": 1'
assert_json_contains "$identical_out/summary.json" '"ssim": 1'
assert_json_contains "$identical_out/summary.json" '"surface_id": "01"'
assert_json_contains "$identical_out/summary.json" '"path": "baseline image.png"'
assert_file "$identical_out/diff-heatmap.png"
assert_file "$identical_out/side-by-side.png"
assert_file "$identical_out/overlay.png"
summary_sha=$(file_sha "$identical_out/summary.json")
heatmap_sha=$(file_sha "$identical_out/diff-heatmap.png")
side_by_side_sha=$(file_sha "$identical_out/side-by-side.png")
overlay_sha=$(file_sha "$identical_out/overlay.png")
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --out "$identical_out" "$baseline" "$identical" >/dev/null
[[ "$(file_sha "$identical_out/summary.json")" == "$summary_sha" ]] || fail "summary is not deterministic"
[[ "$(file_sha "$identical_out/diff-heatmap.png")" == "$heatmap_sha" ]] || fail "heatmap is not deterministic"
[[ "$(file_sha "$identical_out/side-by-side.png")" == "$side_by_side_sha" ]] || fail "side-by-side image is not deterministic"
[[ "$(file_sha "$identical_out/overlay.png")" == "$overlay_sha" ]] || fail "overlay image is not deterministic"

changed_out="$fixture_dir/changed output"
changed_status=0
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --threshold 0 \
    --out "$changed_out" "$baseline" "$changed" || changed_status=$?
[[ "$changed_status" -eq 1 ]] || fail "changed image should exceed the zero threshold"
assert_json_contains "$changed_out/summary.json" '"status": "threshold_exceeded"'
assert_json_contains "$changed_out/summary.json" '"changed_pixels": 1'
assert_json_contains "$changed_out/summary.json" '"changed_ratio": 0.0625'
assert_json_contains "$changed_out/summary.json" '"changed_similarity": 0.9375'

allowed_out="$fixture_dir/allowed output"
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --threshold 0.0625 --min-ssim 0 \
    --out "$allowed_out" "$baseline" "$changed"
assert_json_contains "$allowed_out/summary.json" '"status": "passed"'

ssim_out="$fixture_dir/ssim output"
ssim_status=0
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --threshold 1 --min-ssim 0.90 \
    --out "$ssim_out" "$baseline" "$changed" || ssim_status=$?
[[ "$ssim_status" -eq 1 ]] || fail "changed image should fall below the SSIM threshold"
assert_json_contains "$ssim_out/summary.json" '"ssim_below_minimum": true'

rmse_out="$fixture_dir/rmse output"
rmse_status=0
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --threshold 1 --max-rmse 0.1 \
    --out "$rmse_out" "$baseline" "$changed" || rmse_status=$?
[[ "$rmse_status" -eq 1 ]] || fail "changed image should exceed the RMSE threshold"
assert_json_contains "$rmse_out/summary.json" '"normalized_rmse_exceeded": true'

tolerance_out="$fixture_dir/tolerance output"
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --out "$tolerance_out" "$baseline" "$near_color"
assert_json_contains "$tolerance_out/summary.json" '"channel_delta": 8'
assert_json_contains "$tolerance_out/summary.json" '"changed_pixels": 0'

beyond_tolerance_out="$fixture_dir/beyond tolerance output"
beyond_tolerance_status=0
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --threshold 0 --min-ssim 0 \
    --out "$beyond_tolerance_out" "$baseline" "$beyond_tolerance" || beyond_tolerance_status=$?
[[ "$beyond_tolerance_status" -eq 1 ]] || fail "a nine-level channel change should exceed tolerance"
assert_json_contains "$beyond_tolerance_out/summary.json" '"changed_pixels": 16'

exact_color_out="$fixture_dir/exact color output"
exact_color_status=0
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --channel-delta 0 --threshold 0 --min-ssim 0 \
    --out "$exact_color_out" "$baseline" "$near_color" || exact_color_status=$?
[[ "$exact_color_status" -eq 1 ]] || fail "zero channel tolerance should detect the color change"
assert_json_contains "$exact_color_out/summary.json" '"changed_pixels": 16'

masked_out="$fixture_dir/masked output"
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --mask "$mask" --out "$masked_out" "$baseline" "$changed"
assert_json_contains "$masked_out/summary.json" '"applied": true'
assert_json_contains "$masked_out/summary.json" '"ignored_pixels": 1'
assert_json_contains "$masked_out/summary.json" '"changed_pixels": 0'
assert_json_contains "$masked_out/summary.json" '"ignored_bounds": {"x": 1, "y": 1, "width": 1, "height": 1}'

relaxed_channel_status=0
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --channel-delta 9 \
    --out "$fixture_dir/invalid channel output" "$baseline" "$identical" \
    >/dev/null 2>&1 || relaxed_channel_status=$?
[[ "$relaxed_channel_status" -eq 2 ]] || fail "channel-delta above eight must be rejected"

dimension_out="$fixture_dir/dimension output"
dimension_status=0
"$compare_script" --magick "$magick_bin" "${metadata_args[@]}" --out "$dimension_out" "$baseline" "$wrong_size" \
    >/dev/null 2>&1 || dimension_status=$?
[[ "$dimension_status" -eq 2 ]] || fail "dimension mismatch should exit 2"
/usr/bin/plutil -convert json -o /dev/null -- "$dimension_out/summary.json"
assert_json_contains "$dimension_out/summary.json" '"status": "dimension_mismatch"'

large_baseline="$fixture_dir/large baseline.png"
large_changed="$fixture_dir/large changed.png"
scientific_magick="$fixture_dir/scientific magick wrapper.sh"
scientific_marker="$fixture_dir/scientific count marker.txt"
"$magick_bin" -size 1206x2622 xc:white "$large_baseline"
"$magick_bin" -size 1206x2622 xc:black "$large_changed"
cat > "$scientific_magick" <<'WRAPPER'
#!/usr/bin/env bash

set -euo pipefail

: "${REAL_MAGICK:?}"
: "${SCIENTIFIC_MARKER:?}"

is_pixel_count=false
for argument in "$@"; do
    if [[ "$argument" == '%[fx:round(mean*w*h)]' ]]; then
        is_pixel_count=true
        break
    fi
done

if [[ "$is_pixel_count" == true ]]; then
    exact_value=$("$REAL_MAGICK" "$@")
    scientific_value=$(awk -v value="$exact_value" 'BEGIN { printf "%.12e", value + 0 }')
    printf '%s' "$scientific_value"
    printf '%s\n' "$scientific_value" >> "$SCIENTIFIC_MARKER"
    exit 0
fi

exec "$REAL_MAGICK" "$@"
WRAPPER
chmod +x "$scientific_magick"

large_out="$fixture_dir/large scientific output"
large_status=0
REAL_MAGICK="$magick_bin" SCIENTIFIC_MARKER="$scientific_marker" \
    "$compare_script" --magick "$scientific_magick" "${metadata_args[@]}" --threshold 0.999999 \
    --out "$large_out" "$large_baseline" "$large_changed" || large_status=$?
[[ "$large_status" -eq 1 ]] || fail "large changed image should exceed a nonzero threshold"
/usr/bin/grep -Fxq '3.162132000000e+06' "$scientific_marker" || \
    fail "large fixture did not exercise exact scientific notation"
/usr/bin/plutil -convert json -o /dev/null -- "$large_out/summary.json"
assert_json_contains "$large_out/summary.json" '"status": "threshold_exceeded"'
assert_json_contains "$large_out/summary.json" '"max_changed_ratio": 0.999999'
assert_json_contains "$large_out/summary.json" '"changed_ratio_exceeded": true'
assert_json_integer "$large_out/summary.json" 'comparison.changed_pixels' '3162132'
assert_json_integer "$large_out/summary.json" 'comparison.evaluated_pixels' '3162132'
assert_file "$large_out/diff-heatmap.png"
assert_file "$large_out/side-by-side.png"
assert_file "$large_out/overlay.png"

printf 'visual diff self-test passed (%s)\n' "$fixture_dir"
