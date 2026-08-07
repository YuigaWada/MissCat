#!/usr/bin/env bash

set -euo pipefail

readonly DEFAULT_MAGICK="/opt/homebrew/bin/magick"
readonly SCHEMA_VERSION=4

usage() {
    cat <<'USAGE'
Usage:
  scripts/compare-screenshots.sh [options] BASELINE.png CANDIDATE.png

Options:
  --out DIR                 Artifact directory (default: beside candidate)
  --threshold RATIO         Maximum changed-pixel ratio, 0...1 (default: 0.10)
  --min-ssim VALUE          Minimum SSIM similarity, 0...1 (default: 0.90)
  --channel-delta VALUE     Per-channel change threshold, 0...8 (default: 8)
  --max-rmse VALUE          Optional maximum normalized RMSE, 0...1
  --fuzz PERCENT            Diagnostic RMSE fuzz, 0...100% (default: 0%)
  --mask MASK.png           Explicit mask: white compares, black ignores
  --surface-id ID           Two-digit migration surface ID (required)
  --state TOKEN             Deterministic visual state (required)
  --appearance TOKEN        Appearance axis (required)
  --device TOKEN            Device/runtime axis (required)
  --orientation TOKEN       Capture orientation axis (required)
  --fixture TOKEN           Deterministic fixture ID (required)
  --locale TOKEN            Locale axis (required)
  --content-size TOKEN      Content-size axis (required)
  --visual-ready TOKEN      Accessibility readiness signal (required)
  --record-relative-to DIR  Store artifact paths relative to this canonical root
  --magick PATH             ImageMagick executable (default: /opt/homebrew/bin/magick)
  -h, --help                Show this help

Exit status: 0 passed, 1 threshold exceeded, 2 usage/input/tooling error.
USAGE
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 2
}

require_value() {
    [[ $# -ge 2 ]] || fail "$1 requires a value"
}

absolute_existing_file() {
    local source_path="$1"
    [[ -f "$source_path" ]] || fail "file not found: $source_path"
    local source_dir source_name
    source_dir=$(dirname "$source_path")
    source_name=$(basename "$source_path")
    /bin/realpath "$(cd "$source_dir" && pwd -P)/$source_name"
}

absolute_existing_directory() {
    local target_path="$1"
    [[ -d "$target_path" ]] || fail "directory not found: $target_path"
    /bin/realpath "$target_path"
}

absolute_directory() {
    local target_path="$1"
    mkdir -p "$target_path"
    printf '%s' "$(cd "$target_path" && pwd -P)"
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

record_path() {
    local absolute_path="$1"
    if [[ -z "$record_root" ]]; then
        printf '%s' "$absolute_path"
        return
    fi
    case "$absolute_path" in
        "$record_root"/*) printf '%s' "${absolute_path#${record_root}/}" ;;
        *) fail "recorded path escapes --record-relative-to: $absolute_path" ;;
    esac
}

is_token() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

sha256() {
    /usr/bin/openssl dgst -sha256 -r "$1" | awk '{ print $1 }'
}

dimensions() {
    local image_path="$1"
    local result
    result=$("$magick_bin" identify -format '%w %h\n' "$image_path") || fail "cannot read image: $image_path"
    [[ "$result" != *$'\n'* ]] || fail "multi-frame images are not supported: $image_path"
    [[ "$result" =~ ^[0-9]+\ [0-9]+$ ]] || fail "invalid image dimensions: $image_path"
    printf '%s' "$result"
}

is_ratio() {
    awk -v value="$1" 'BEGIN {
        if (value !~ /^[0-9]+([.][0-9]+)?$/) exit 1
        exit !(value >= 0 && value <= 1)
    }'
}

normalize_number() {
    awk -v value="$1" 'BEGIN { printf "%.12g", value + 0 }'
}

normalize_pixel_count() {
    local value="$1"
    local maximum="$2"
    LC_ALL=C awk -v value="$value" -v maximum="$maximum" 'BEGIN {
        if (value !~ /^[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$/) exit 1
        numeric = value + 0
        if (numeric < 0 || numeric > maximum || numeric != int(numeric)) exit 1
        printf "%.0f", numeric
    }'
}

write_validation_report() {
    local status="$1"
    local detail="$2"
    cat > "$summary_path" <<JSON
{
  "schema_version": $SCHEMA_VERSION,
  "status": "$(json_escape "$status")",
  "detail": "$(json_escape "$detail")",
  "capture": {
    "surface_id": "$(json_escape "$surface_id")",
    "state": "$(json_escape "$state")",
    "appearance": "$(json_escape "$appearance")",
    "device": "$(json_escape "$device")",
    "orientation": "$(json_escape "$orientation")",
    "fixture": "$(json_escape "$fixture")",
    "locale": "$(json_escape "$locale")",
    "content_size": "$(json_escape "$content_size")",
    "visual_ready": "$(json_escape "$visual_ready")"
  },
  "baseline": {
    "path": "$(json_escape "$baseline_record")",
    "sha256": "$baseline_sha",
    "width": $baseline_width,
    "height": $baseline_height
  },
  "candidate": {
    "path": "$(json_escape "$candidate_record")",
    "sha256": "$candidate_sha",
    "width": $candidate_width,
    "height": $candidate_height
  },
  "comparison": {
    "fuzz_percent": $fuzz_number,
    "channel_delta": $channel_delta,
    "max_changed_ratio": $threshold,
    "min_ssim": $min_ssim,
    "max_normalized_rmse": $max_rmse_json
  },
  "mask": {
    "requested": $mask_requested,
    "applied": false,
    "path": $mask_path_json,
    "sha256": $mask_sha_json,
    "ignored_pixels": 0,
    "ignored_bounds": null
  },
  "artifacts": {
    "summary": "$(json_escape "$summary_record")",
    "heatmap": null,
    "side_by_side": null,
    "overlay": null
  }
}
JSON
}

baseline_input=""
candidate_input=""
out_input=""
threshold="0.10"
min_ssim="0.90"
channel_delta="8"
max_rmse=""
fuzz="0%"
mask_input=""
magick_bin="$DEFAULT_MAGICK"
surface_id=""
state=""
appearance=""
device=""
orientation=""
fixture=""
locale=""
content_size=""
visual_ready=""
record_relative_to_input=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)
            require_value "$@"
            out_input="$2"
            shift 2
            ;;
        --threshold)
            require_value "$@"
            threshold="$2"
            shift 2
            ;;
        --max-rmse)
            require_value "$@"
            max_rmse="$2"
            shift 2
            ;;
        --min-ssim)
            require_value "$@"
            min_ssim="$2"
            shift 2
            ;;
        --channel-delta)
            require_value "$@"
            channel_delta="$2"
            shift 2
            ;;
        --fuzz)
            require_value "$@"
            fuzz="$2"
            shift 2
            ;;
        --mask)
            require_value "$@"
            mask_input="$2"
            shift 2
            ;;
        --surface-id)
            require_value "$@"
            surface_id="$2"
            shift 2
            ;;
        --state)
            require_value "$@"
            state="$2"
            shift 2
            ;;
        --appearance)
            require_value "$@"
            appearance="$2"
            shift 2
            ;;
        --device)
            require_value "$@"
            device="$2"
            shift 2
            ;;
        --orientation)
            require_value "$@"
            orientation="$2"
            shift 2
            ;;
        --fixture)
            require_value "$@"
            fixture="$2"
            shift 2
            ;;
        --locale)
            require_value "$@"
            locale="$2"
            shift 2
            ;;
        --content-size)
            require_value "$@"
            content_size="$2"
            shift 2
            ;;
        --visual-ready)
            require_value "$@"
            visual_ready="$2"
            shift 2
            ;;
        --record-relative-to)
            require_value "$@"
            record_relative_to_input="$2"
            shift 2
            ;;
        --magick)
            require_value "$@"
            magick_bin="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            ;;
        -*)
            fail "unknown option: $1"
            ;;
        *)
            if [[ -z "$baseline_input" ]]; then
                baseline_input="$1"
            elif [[ -z "$candidate_input" ]]; then
                candidate_input="$1"
            else
                fail "unexpected positional argument: $1"
            fi
            shift
            ;;
    esac
done

[[ -n "$baseline_input" && -n "$candidate_input" ]] || {
    usage >&2
    exit 2
}
[[ -x "$magick_bin" ]] || fail "ImageMagick executable is unavailable: $magick_bin"
[[ "$surface_id" =~ ^[0-9][0-9]$ ]] || fail "surface-id must be two digits"
for metadata in "$state" "$appearance" "$device" "$orientation" "$fixture" "$locale" "$content_size" "$visual_ready"; do
    is_token "$metadata" || fail "all capture metadata fields are required canonical tokens"
done
is_ratio "$threshold" || fail "threshold must be between 0 and 1: $threshold"
is_ratio "$min_ssim" || fail "min-ssim must be between 0 and 1: $min_ssim"
[[ "$channel_delta" =~ ^[0-9]+$ ]] || fail "channel-delta must be an integer from 0 to 8: $channel_delta"
[[ "$channel_delta" -le 8 ]] || fail "channel-delta must be an integer from 0 to 8: $channel_delta"
if [[ -n "$max_rmse" ]]; then
    is_ratio "$max_rmse" || fail "max-rmse must be between 0 and 1: $max_rmse"
fi
[[ "$fuzz" =~ ^[0-9]+([.][0-9]+)?%$ ]] || fail "fuzz must be a percentage such as 0% or 1.5%"
fuzz_number=${fuzz%%%}
awk -v value="$fuzz_number" 'BEGIN { exit !(value >= 0 && value <= 100) }' || fail "fuzz must be between 0% and 100%: $fuzz"

threshold=$(normalize_number "$threshold")
min_ssim=$(normalize_number "$min_ssim")
fuzz_number=$(normalize_number "$fuzz_number")
channel_delta_percent=$(awk -v value="$channel_delta" \
    'BEGIN { printf "%.12g%%", 100 * value / 255 }')
if [[ -n "$max_rmse" ]]; then
    max_rmse=$(normalize_number "$max_rmse")
    max_rmse_json="$max_rmse"
else
    max_rmse_json="null"
fi

baseline=$(absolute_existing_file "$baseline_input")
candidate=$(absolute_existing_file "$candidate_input")
record_root=""
if [[ -n "$record_relative_to_input" ]]; then
    record_root=$(absolute_existing_directory "$record_relative_to_input")
fi
mask=""
mask_requested="false"
mask_path_json="null"
mask_sha_json="null"
if [[ -n "$mask_input" ]]; then
    mask=$(absolute_existing_file "$mask_input")
    mask_requested="true"
    mask_path_json="\"$(json_escape "$(record_path "$mask")")\""
    mask_sha_json="\"$(sha256 "$mask")\""
fi

if [[ -z "$out_input" ]]; then
    baseline_stem=$(basename "$baseline")
    baseline_stem=${baseline_stem%.*}
    candidate_stem=$(basename "$candidate")
    candidate_stem=${candidate_stem%.*}
    out_input="$(dirname "$candidate")/visual-diff/${baseline_stem}__vs__${candidate_stem}"
fi
out_dir=$(absolute_directory "$out_input")
summary_path="$out_dir/summary.json"
heatmap_path="$out_dir/diff-heatmap.png"
side_by_side_path="$out_dir/side-by-side.png"
overlay_path="$out_dir/overlay.png"
baseline_record=$(record_path "$baseline")
candidate_record=$(record_path "$candidate")
summary_record=$(record_path "$summary_path")
heatmap_record=$(record_path "$heatmap_path")
side_by_side_record=$(record_path "$side_by_side_path")
overlay_record=$(record_path "$overlay_path")

read -r baseline_width baseline_height <<< "$(dimensions "$baseline")"
read -r candidate_width candidate_height <<< "$(dimensions "$candidate")"
baseline_sha=$(sha256 "$baseline")
candidate_sha=$(sha256 "$candidate")

if [[ "$baseline_width" -ne "$candidate_width" || "$baseline_height" -ne "$candidate_height" ]]; then
    write_validation_report "dimension_mismatch" "baseline and candidate dimensions must match"
    printf 'dimension mismatch: baseline=%sx%s candidate=%sx%s\n' \
        "$baseline_width" "$baseline_height" "$candidate_width" "$candidate_height" >&2
    exit 2
fi

total_pixels=$((baseline_width * baseline_height))
evaluated_pixels=$total_pixels
ignored_pixels=0
mask_applied="false"
ignored_bounds_json="null"

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/misscat-visual-diff.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT
effective_baseline="$baseline"
effective_candidate="$candidate"

if [[ -n "$mask" ]]; then
    read -r mask_width mask_height <<< "$(dimensions "$mask")"
    if [[ "$mask_width" -ne "$baseline_width" || "$mask_height" -ne "$baseline_height" ]]; then
        write_validation_report "mask_dimension_mismatch" "mask dimensions must match the screenshots"
        printf 'mask dimension mismatch: mask=%sx%s screenshot=%sx%s\n' \
            "$mask_width" "$mask_height" "$baseline_width" "$baseline_height" >&2
        exit 2
    fi

    effective_mask="$temporary_dir/effective-mask.png"
    effective_baseline="$temporary_dir/baseline-masked.png"
    effective_candidate="$temporary_dir/candidate-masked.png"
    "$magick_bin" "$mask" -alpha off -colorspace Gray -threshold 50% "$effective_mask"
    evaluated_pixels_output=$("$magick_bin" -precision 20 "$effective_mask" \
        -format '%[fx:round(w*h*mean)]' info:)
    evaluated_pixels=$(normalize_pixel_count "$evaluated_pixels_output" "$total_pixels") || \
        fail "could not count mask pixels: $evaluated_pixels_output"
    [[ "$evaluated_pixels" -gt 0 ]] || fail "mask ignores every screenshot pixel"
    ignored_pixels=$((total_pixels - evaluated_pixels))
    [[ "$ignored_pixels" -gt 0 ]] || fail "mask must ignore at least one screenshot pixel"

    ignored_mask="$temporary_dir/ignored-mask.png"
    "$magick_bin" "$effective_mask" -negate "$ignored_mask"
    # A known black border makes the trim background deterministic even when
    # the ignored region touches the image's top-left pixel. The page offset
    # includes that one-pixel border, so translate it back to image space.
    ignored_geometry=$("$magick_bin" "$ignored_mask" -bordercolor black -border 1 -trim -format '%wx%h%O' info:)
    [[ "$ignored_geometry" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]] || \
        fail "could not determine ignored mask bounds: $ignored_geometry"
    ignored_width="${BASH_REMATCH[1]}"
    ignored_height="${BASH_REMATCH[2]}"
    ignored_x=$((BASH_REMATCH[3] - 1))
    ignored_y=$((BASH_REMATCH[4] - 1))
    ignored_bounds_json="{\"x\": $ignored_x, \"y\": $ignored_y, \"width\": $ignored_width, \"height\": $ignored_height}"

    "$magick_bin" "$baseline" -alpha off "$effective_mask" -compose Multiply -composite "$effective_baseline"
    "$magick_bin" "$candidate" -alpha off "$effective_mask" -compose Multiply -composite "$effective_candidate"

    mask_applied="true"
fi

binary_diff="$temporary_dir/changed-pixels.png"
channel_difference="$temporary_dir/channel-difference.png"
"$magick_bin" "$effective_baseline" "$effective_candidate" \
    -alpha off -compose Difference -composite -separate -evaluate-sequence Max \
    "$channel_difference"
"$magick_bin" "$channel_difference" -threshold "$channel_delta_percent" "$binary_diff"
changed_pixels_output=$("$magick_bin" -precision 20 "$binary_diff" -alpha off -colorspace Gray \
    -threshold 50% -format '%[fx:round(mean*w*h)]' info:)
changed_pixels=$(normalize_pixel_count "$changed_pixels_output" "$evaluated_pixels") || \
    fail "could not count changed pixels: $changed_pixels_output"
changed_ratio=$(awk -v changed="$changed_pixels" -v total="$evaluated_pixels" \
    'BEGIN { printf "%.12g", changed / total }')
changed_similarity=$(awk -v ratio="$changed_ratio" \
    'BEGIN { printf "%.12g", 1 - ratio }')

rmse_output=""
rmse_status=0
set +e
rmse_output=$("$magick_bin" compare -fuzz "$fuzz" -metric RMSE \
    "$effective_baseline" "$effective_candidate" null: 2>&1)
rmse_status=$?
set -e
[[ "$rmse_status" -le 1 ]] || fail "ImageMagick RMSE comparison failed: $rmse_output"
rmse_absolute=$(printf '%s\n' "$rmse_output" | awk '{ print $1 }')
rmse_normalized=$(printf '%s\n' "$rmse_output" | awk -F '[()]' '{ print $2 }')
[[ "$rmse_absolute" =~ ^[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$ ]] || fail "unexpected absolute RMSE metric: $rmse_output"
[[ "$rmse_normalized" =~ ^[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$ ]] || fail "unexpected normalized RMSE metric: $rmse_output"
rmse_absolute=$(normalize_number "$rmse_absolute")
rmse_normalized=$(normalize_number "$rmse_normalized")
if [[ "$evaluated_pixels" -ne "$total_pixels" ]]; then
    rmse_absolute=$(awk -v value="$rmse_absolute" -v total="$total_pixels" -v evaluated="$evaluated_pixels" \
        'BEGIN { printf "%.12g", value * sqrt(total / evaluated) }')
    rmse_normalized=$(awk -v value="$rmse_normalized" -v total="$total_pixels" -v evaluated="$evaluated_pixels" \
        'BEGIN { printf "%.12g", value * sqrt(total / evaluated) }')
fi

ssim_output=""
ssim_status=0
set +e
ssim_output=$("$magick_bin" compare -metric SSIM \
    "$effective_baseline" "$effective_candidate" null: 2>&1)
ssim_status=$?
set -e
[[ "$ssim_status" -le 1 ]] || fail "ImageMagick SSIM comparison failed: $ssim_output"
ssim_normalized=$(printf '%s\n' "$ssim_output" | awk -F '[()]' '{ print $2 }')
[[ "$ssim_normalized" =~ ^[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$ ]] || \
    fail "unexpected SSIM metric: $ssim_output"
ssim_normalized=$(normalize_number "$ssim_normalized")
if [[ "$evaluated_pixels" -ne "$total_pixels" ]]; then
    # Both masked inputs contain identical black pixels. Remove their ideal
    # contribution from ImageMagick's whole-canvas mean so the score remains
    # normalized to the app-owned pixels evaluated by the changed-pixel gate.
    ssim_normalized=$(awk \
        -v value="$ssim_normalized" \
        -v total="$total_pixels" \
        -v ignored="$ignored_pixels" \
        -v evaluated="$evaluated_pixels" \
        'BEGIN {
            adjusted = (value * total - ignored) / evaluated
            if (adjusted < 0) adjusted = 0
            if (adjusted > 1) adjusted = 1
            printf "%.12g", adjusted
        }')
fi

raw_heatmap="$temporary_dir/diff-heatmap.png"
"$magick_bin" "$binary_diff" \
    -fill '#ff0055' -opaque white \
    -fill '#101010' -opaque black \
    "$raw_heatmap"
"$magick_bin" "$raw_heatmap" -strip -define png:exclude-chunks=date,time "$heatmap_path"
"$magick_bin" "$baseline" "$candidate" +append -strip -define png:exclude-chunks=date,time "$side_by_side_path"
"$magick_bin" "$baseline" "$candidate" -define compose:args=50 -compose Blend -composite \
    -strip -define png:exclude-chunks=date,time "$overlay_path"

ratio_exceeded=$(awk -v actual="$changed_ratio" -v maximum="$threshold" \
    'BEGIN { print (actual > maximum) ? 1 : 0 }')
ssim_below_minimum=$(awk -v actual="$ssim_normalized" -v minimum="$min_ssim" \
    'BEGIN { print (actual < minimum) ? 1 : 0 }')
rmse_exceeded=0
if [[ -n "$max_rmse" ]]; then
    rmse_exceeded=$(awk -v actual="$rmse_normalized" -v maximum="$max_rmse" \
        'BEGIN { print (actual > maximum) ? 1 : 0 }')
fi

status="passed"
exit_status=0
if [[ "$ratio_exceeded" -eq 1 || "$ssim_below_minimum" -eq 1 || "$rmse_exceeded" -eq 1 ]]; then
    status="threshold_exceeded"
    exit_status=1
fi

cat > "$summary_path" <<JSON
{
  "schema_version": $SCHEMA_VERSION,
  "status": "$status",
  "capture": {
    "surface_id": "$(json_escape "$surface_id")",
    "state": "$(json_escape "$state")",
    "appearance": "$(json_escape "$appearance")",
    "device": "$(json_escape "$device")",
    "orientation": "$(json_escape "$orientation")",
    "fixture": "$(json_escape "$fixture")",
    "locale": "$(json_escape "$locale")",
    "content_size": "$(json_escape "$content_size")",
    "visual_ready": "$(json_escape "$visual_ready")"
  },
  "baseline": {
    "path": "$(json_escape "$baseline_record")",
    "sha256": "$baseline_sha",
    "width": $baseline_width,
    "height": $baseline_height
  },
  "candidate": {
    "path": "$(json_escape "$candidate_record")",
    "sha256": "$candidate_sha",
    "width": $candidate_width,
    "height": $candidate_height
  },
  "comparison": {
    "fuzz_percent": $fuzz_number,
    "channel_delta": $channel_delta,
    "changed_pixels": $changed_pixels,
    "evaluated_pixels": $evaluated_pixels,
    "changed_ratio": $changed_ratio,
    "changed_similarity": $changed_similarity,
    "ssim": $ssim_normalized,
    "rmse_absolute": $rmse_absolute,
    "rmse_normalized": $rmse_normalized,
    "max_changed_ratio": $threshold,
    "min_ssim": $min_ssim,
    "max_normalized_rmse": $max_rmse_json,
    "changed_ratio_exceeded": $([[ "$ratio_exceeded" -eq 1 ]] && printf true || printf false),
    "ssim_below_minimum": $([[ "$ssim_below_minimum" -eq 1 ]] && printf true || printf false),
    "normalized_rmse_exceeded": $([[ "$rmse_exceeded" -eq 1 ]] && printf true || printf false)
  },
  "mask": {
    "requested": $mask_requested,
    "applied": $mask_applied,
    "path": $mask_path_json,
    "sha256": $mask_sha_json,
    "ignored_pixels": $ignored_pixels,
    "ignored_bounds": $ignored_bounds_json
  },
  "artifacts": {
    "summary": "$(json_escape "$summary_record")",
    "heatmap": "$(json_escape "$heatmap_record")",
    "side_by_side": "$(json_escape "$side_by_side_record")",
    "overlay": "$(json_escape "$overlay_record")"
  }
}
JSON

printf '%s: changed=%s/%s similarity=%s ssim=%s rmse=%s summary=%s\n' \
    "$status" "$changed_pixels" "$evaluated_pixels" "$changed_similarity" \
    "$ssim_normalized" "$rmse_normalized" "$summary_path"
exit "$exit_status"
