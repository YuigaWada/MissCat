#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly gate="$script_dir/compare-screenshot-regions.sh"
readonly magick_bin="${MAGICK_BIN:-/opt/homebrew/bin/magick}"
readonly canonical_manifest="$script_dir/fixtures/visual-regions/timeline-selftest-v1.json"

fail() {
    printf 'region self-test failed: %s\n' "$*" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

assert_json() {
    local path="$1"
    local expression="$2"
    /usr/bin/ruby -rjson -e "data = JSON.parse(File.read(ARGV.fetch(0))); abort unless (${expression})" "$path" || \
        fail "JSON assertion failed for $path: $expression"
}

file_sha() {
    /usr/bin/openssl dgst -sha256 -r "$1" | /usr/bin/awk '{ print $1 }'
}

run_expect() {
    local expected_status="$1"
    local expected_error="$2"
    shift 2
    local status=0
    "$gate" --magick "$magick_bin" "$@" >"$fixture_dir/stdout" 2>"$fixture_dir/stderr" || status=$?
    [[ "$status" -eq "$expected_status" ]] || \
        fail "expected exit $expected_status, got $status: $(<"$fixture_dir/stderr")"
    if [[ -n "$expected_error" ]]; then
        /usr/bin/grep -Fq "$expected_error" "$fixture_dir/stderr" || \
            fail "stderr does not contain '$expected_error': $(<"$fixture_dir/stderr")"
    fi
}

[[ -x "$magick_bin" ]] || fail "ImageMagick is unavailable: $magick_bin"
[[ -x "$gate" ]] || fail "region comparison gate is not executable: $gate"
[[ -f "$canonical_manifest" ]] || fail "missing canonical fixture manifest"

fixture_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/misscat region gate test.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT

baseline="$fixture_dir/baseline.png"
identical="$fixture_dir/identical.png"
metric_failure="$fixture_dir/metric failure.png"
shifted_icon="$fixture_dir/shifted icon.png"
wrong_size="$fixture_dir/wrong size.png"

"$magick_bin" -size 200x120 xc:white \
    -fill '#202020' \
    -draw 'rectangle 10,10 70,15 rectangle 20,42 155,63 rectangle 25,91 34,100' \
    "$baseline"
"$magick_bin" "$baseline" "$identical"
"$magick_bin" "$baseline" -fill black -draw 'rectangle 0,30 199,79' "$metric_failure"
"$magick_bin" "$baseline" -fill white -draw 'rectangle 23,89 36,102' \
    -fill '#202020' -draw 'rectangle 35,91 44,100' "$shifted_icon"
"$magick_bin" -size 199x120 xc:white "$wrong_size"

pass_out="$fixture_dir/pass output"
run_expect 0 '' --manifest "$canonical_manifest" --out "$pass_out" "$baseline" "$identical"
assert_file "$pass_out/summary.json"
assert_file "$pass_out/summary.tsv"
assert_json "$pass_out/summary.json" 'data["status"] == "passed" && data["regions"].length == 3'
/usr/bin/grep -Fqx $'region_id\towner\tkind\tx\ty\twidth\theight\tchanged_similarity\tssim\tedge_coverage\tstatus\tdetail' \
    <(/usr/bin/head -n 1 "$pass_out/summary.tsv") || fail "unexpected TSV header"
for region in timeline-tabs note-body note-actions; do
    assert_file "$pass_out/regions/$region/summary.json"
    assert_file "$pass_out/regions/$region/diff-amplified.png"
    assert_file "$pass_out/regions/$region/side-by-side-amplified.png"
done
assert_file "$pass_out/regions/note-actions/edge-coverage-amplified.png"

summary_sha=$(file_sha "$pass_out/summary.json")
tsv_sha=$(file_sha "$pass_out/summary.tsv")
amplified_sha=$(file_sha "$pass_out/regions/note-actions/diff-amplified.png")
run_expect 0 '' --manifest "$canonical_manifest" --out "$pass_out" "$baseline" "$identical"
[[ "$(file_sha "$pass_out/summary.json")" == "$summary_sha" ]] || fail "JSON output is not deterministic"
[[ "$(file_sha "$pass_out/summary.tsv")" == "$tsv_sha" ]] || fail "TSV output is not deterministic"
[[ "$(file_sha "$pass_out/regions/note-actions/diff-amplified.png")" == "$amplified_sha" ]] || \
    fail "amplified diff is not deterministic"

metric_out="$fixture_dir/metric output"
run_expect 1 'one or more app-owned regions failed' \
    --manifest "$canonical_manifest" --out "$metric_out" "$baseline" "$metric_failure"
assert_json "$metric_out/summary.json" \
    'data["status"] == "failed" && data["regions"].find { |r| r["id"] == "note-body" }["status"] == "failed"'

# A ten-pixel move of a sparse icon changes far below 10% of its white region.
# Pixel similarity and SSIM therefore pass, while the two-pixel edge gate must fail.
shift_out="$fixture_dir/shift output"
run_expect 1 'one or more app-owned regions failed' \
    --manifest "$canonical_manifest" --out "$shift_out" "$baseline" "$shifted_icon"
assert_json "$shift_out/summary.json" \
    'r = data["regions"].find { |row| row["id"] == "note-actions" }; r["changed_similarity"] >= 0.9 && r["ssim"] >= 0.9 && r["edge_coverage"] < 0.9 && r["status"] == "failed"'

run_expect 2 'baseline and candidate dimensions differ' \
    --manifest "$canonical_manifest" --out "$fixture_dir/dimension output" "$baseline" "$wrong_size"

missing_manifest="$fixture_dir/missing region.json"
duplicate_manifest="$fixture_dir/duplicate region.json"
out_of_bounds_manifest="$fixture_dir/out of bounds.json"
wrong_canvas_manifest="$fixture_dir/wrong canvas.json"
/usr/bin/ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  data["regions"].reject! { |region| region["id"] == "note-actions" }
  File.write(ARGV.fetch(1), JSON.pretty_generate(data) + "\n")
' "$canonical_manifest" "$missing_manifest"
/usr/bin/ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  data["regions"] << data["regions"].first.dup
  File.write(ARGV.fetch(1), JSON.pretty_generate(data) + "\n")
' "$canonical_manifest" "$duplicate_manifest"
/usr/bin/ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  data["regions"].first["x"] = 199
  data["regions"].first["width"] = 2
  File.write(ARGV.fetch(1), JSON.pretty_generate(data) + "\n")
' "$canonical_manifest" "$out_of_bounds_manifest"
/usr/bin/ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  data["canvas"]["width"] = 201
  File.write(ARGV.fetch(1), JSON.pretty_generate(data) + "\n")
' "$canonical_manifest" "$wrong_canvas_manifest"

run_expect 2 'missing required regions: note-actions' \
    --manifest "$missing_manifest" --out "$fixture_dir/missing output" "$baseline" "$identical"
run_expect 2 'duplicate region id: timeline-tabs' \
    --manifest "$duplicate_manifest" --out "$fixture_dir/duplicate output" "$baseline" "$identical"
run_expect 2 'region is out of canvas bounds: timeline-tabs' \
    --manifest "$out_of_bounds_manifest" --out "$fixture_dir/bounds output" "$baseline" "$identical"
run_expect 2 'screenshots do not match manifest canvas' \
    --manifest "$wrong_canvas_manifest" --out "$fixture_dir/canvas output" "$baseline" "$identical"

printf 'timeline named-region visual gate self-test passed (%s)\n' "$fixture_dir"
