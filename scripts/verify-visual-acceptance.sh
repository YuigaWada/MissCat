#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repository_root="$(cd "${script_dir}/.." && pwd -P)"
readonly json_validator="${script_dir}/validate-visual-evidence-json.rb"
readonly comparator="${script_dir}/compare-screenshots.sh"
readonly REQUIREMENTS_SCHEMA_VERSION=2
readonly EVIDENCE_SCHEMA_VERSION=2
readonly SUMMARY_SCHEMA_VERSION=4
readonly REVIEW_SCHEMA_VERSION=1
readonly EXPECTED_REQUIREMENTS_SHA256="165e3faaaffe757219c684eb0d910149a79f5bf68a933e11309ae7edd2bfc2e5"
readonly EXPECTED_CAPTURE_POLICY_SHA256="a4e8ae8bbfd9476a6e44c339b0e2a4f1d7c920936b6af86444af6c746b76b048"
readonly EXPECTED_SURFACES=45
readonly EXPECTED_VISUAL_CASES=698

requirements="${repository_root}/docs/visual-acceptance-requirements.tsv"
evidence="${repository_root}/docs/visual-acceptance-evidence.tsv"
ledger="${repository_root}/docs/ui-migration-surfaces.tsv"
mask_policy="${repository_root}/docs/visual-acceptance-mask-policy.tsv"
mask_policy_approval="${repository_root}/docs/visual-acceptance-mask-policy-approval.tsv"
capture_policy="${repository_root}/docs/visual-acceptance-capture-policy.tsv"
magick_bin="${MAGICK_BIN:-/opt/homebrew/bin/magick}"
mode="--inventory"

usage() {
    cat >&2 <<'USAGE'
usage: scripts/verify-visual-acceptance.sh [--inventory|--require-complete]
       [--requirements PATH] [--evidence PATH] [--ledger PATH]
       [--capture-policy PATH] [--mask-policy PATH]
       [--mask-policy-approval PATH] [--magick PATH]

--inventory validates the pinned 45-surface/698-case contract and every
recorded evidence row. --require-complete additionally rejects missing visual
cases and any non-deferred surface not yet SwiftUI-owned and accepted in the
route ledger.
USAGE
}

fail() {
    printf 'visual acceptance verification failed: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --inventory|--require-complete)
            mode="$1"
            shift
            ;;
        --requirements)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            requirements="$2"
            shift 2
            ;;
        --evidence)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            evidence="$2"
            shift 2
            ;;
        --ledger)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            ledger="$2"
            shift 2
            ;;
        --mask-policy)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            mask_policy="$2"
            shift 2
            ;;
        --mask-policy-approval)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            mask_policy_approval="$2"
            shift 2
            ;;
        --capture-policy)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            capture_policy="$2"
            shift 2
            ;;
        --magick)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            magick_bin="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 64
            ;;
    esac
done

[[ -x "$json_validator" ]] || fail "missing JSON validator: $json_validator"
[[ -x "$comparator" ]] || fail "missing screenshot comparator: $comparator"
[[ -f "$requirements" ]] || fail "missing requirements: $requirements"
[[ -f "$evidence" ]] || fail "missing evidence manifest: $evidence"
[[ -f "$ledger" ]] || fail "missing migration ledger: $ledger"
[[ -f "$mask_policy" ]] || fail "missing mask policy: $mask_policy"
[[ -f "$mask_policy_approval" ]] || fail "missing mask policy approval: $mask_policy_approval"
[[ -f "$capture_policy" ]] || fail "missing capture policy: $capture_policy"

temporary_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/misscat-visual-acceptance.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT
expanded_all="${temporary_dir}/expanded-all.tsv"
expected_cases="${temporary_dir}/expected.tsv"
expected_keys="${temporary_dir}/expected-keys.tsv"
route_audits="${temporary_dir}/route-audits.tsv"
recorded_cases="${temporary_dir}/recorded.tsv"
ledger_ids="${temporary_dir}/ledger-ids.txt"
requirement_ids="${temporary_dir}/requirement-ids.txt"
used_paths="${temporary_dir}/used-paths.txt"
used_baseline_hashes="${temporary_dir}/used-baseline-hashes.txt"
used_candidate_hashes="${temporary_dir}/used-candidate-hashes.txt"
used_pixel_content="${temporary_dir}/used-pixel-content.tsv"
: > "$used_paths"
: > "$used_baseline_hashes"
: > "$used_candidate_hashes"
: > "$used_pixel_content"

sha256_file() {
    /usr/bin/openssl dgst -sha256 -r "$1" | awk '{ print $1 }'
}

is_safe_relative_path() {
    local path="$1"
    [[ -n "$path" && "$path" != /* && "$path" != "." && "$path" != ".." && \
       "$path" != ../* && "$path" != */../* && "$path" != */.. && \
       "$path" =~ ^[A-Za-z0-9._/-]+$ ]]
}

canonical_existing_file() {
    local relative="$1"
    local label="$2"
    is_safe_relative_path "$relative" || fail "unsafe ${label} path: $relative"
    local lexical="${repository_root}/${relative}"
    [[ -f "$lexical" ]] || fail "missing ${label}: $relative"
    local resolved
    resolved=$(/bin/realpath "$lexical") || fail "cannot canonicalize ${label}: $relative"
    [[ "$resolved" == "$lexical" ]] || fail "symlink or aliased ${label} path: $relative"
    case "$resolved" in
        "$repository_root"/*) ;;
        *) fail "${label} escapes repository: $relative" ;;
    esac
    printf '%s' "$resolved"
}

canonical_existing_directory() {
    local relative="$1"
    local label="$2"
    is_safe_relative_path "$relative" || fail "unsafe ${label} path: $relative"
    local lexical="${repository_root}/${relative}"
    [[ -d "$lexical" ]] || fail "missing ${label}: $relative"
    local resolved
    resolved=$(/bin/realpath "$lexical") || fail "cannot canonicalize ${label}: $relative"
    [[ "$resolved" == "$lexical" ]] || fail "symlink or aliased ${label} path: $relative"
    case "$resolved" in
        "$repository_root"/*) ;;
        *) fail "${label} escapes repository: $relative" ;;
    esac
    printf '%s' "$resolved"
}

register_unique_path() {
    local relative="$1"
    local label="$2"
    if /usr/bin/grep -Fqx "$relative" "$used_paths"; then
        fail "reused or replayed evidence path (${label}): $relative"
    fi
    printf '%s\n' "$relative" >> "$used_paths"
}

register_unique_image_content() {
    local digest="$1"
    local registry="$2"
    local label="$3"
    local case_id="$4"
    if /usr/bin/grep -Fqx "$digest" "$registry"; then
        fail "reused or replayed ${label} image content for $case_id"
    fi
    printf '%s\n' "$digest" >> "$registry"
}

register_canonical_pixel_content() {
    local digest="$1"
    local case_id="$2"
    local role="$3"
    local owner
    owner=$(awk -F '\t' -v digest="$digest" '$1 == digest { print $2; exit }' "$used_pixel_content")
    if [[ -n "$owner" && "$owner" != "$case_id" ]]; then
        fail "reused or replayed decoded pixel content (${role}) for $case_id; owned by $owner"
    fi
    if [[ -z "$owner" ]]; then
        printf '%s\t%s\n' "$digest" "$case_id" >> "$used_pixel_content"
    fi
}

image_dimensions() {
    local path="$1"
    local output width height
    output=$(/usr/bin/sips -g pixelWidth -g pixelHeight "$path" 2>/dev/null) || \
        fail "cannot read PNG dimensions: ${path#${repository_root}/}"
    width=$(printf '%s\n' "$output" | awk '/pixelWidth:/ { print $2 }')
    height=$(printf '%s\n' "$output" | awk '/pixelHeight:/ { print $2 }')
    [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ && "$width" -gt 0 && "$height" -gt 0 ]] || \
        fail "invalid PNG dimensions: ${path#${repository_root}/}"
    printf '%s %s' "$width" "$height"
}

canonical_pixel_digest() {
    local path="$1"
    local orientation="$2"
    local width="$3"
    local height="$4"
    local digest
    [[ -x "$magick_bin" ]] || fail "ImageMagick is required to canonicalize capture pixels: $magick_bin"
    digest=$(
        {
            printf 'misscat-rgba8-srgb-v1\0%s\0%s\0%s\0' "$orientation" "$width" "$height"
            "$magick_bin" "$path" -auto-orient -colorspace sRGB -alpha on -depth 8 -strip rgba:-
        } | /usr/bin/openssl dgst -sha256 -r | awk '{ print $1 }'
    ) || fail "cannot canonicalize capture pixels: ${path#${repository_root}/}"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail "invalid canonical pixel digest: ${path#${repository_root}/}"
    printf '%s' "$digest"
}

git_blob_at() {
    local commit="$1"
    local relative="$2"
    git -C "$repository_root" rev-parse "${commit}:${relative}" 2>/dev/null
}

require_immutable_blob() {
    local relative="$1"
    local commit="$2"
    local label="$3"
    local path="$4"
    local evidence_blob head_blob current_blob
    evidence_blob=$(git_blob_at "$commit" "$relative") || \
        fail "${label} was not tracked at evidence_commit: $relative"
    head_blob=$(git_blob_at HEAD "$relative") || fail "${label} is not tracked at HEAD: $relative"
    current_blob=$(git -C "$repository_root" hash-object "$path") || fail "cannot hash ${label}: $relative"
    [[ "$evidence_blob" == "$head_blob" && "$head_blob" == "$current_blob" ]] || \
        fail "${label} blob drifted from evidence_commit: $relative"
}

require_prior_immutable_blob() {
    local relative="$1"
    local commit="$2"
    local label="$3"
    local path="$4"
    local parent
    parent=$(git -C "$repository_root" rev-parse "${commit}^" 2>/dev/null) || \
        fail "evidence_commit has no prior ${label} approval: $commit"
    require_immutable_blob "$relative" "$parent" "$label" "$path"
}

require_artifact_producer() {
    local commit="$1"
    shift
    local ancestry produced produced_count=0 expected_count=$#
    ancestry=$(git -C "$repository_root" rev-list --parents -n 1 "$commit") || \
        fail "cannot inspect artifact-producer commit: $commit"
    [[ "$(printf '%s\n' "$ancestry" | awk '{ print NF }')" -le 2 ]] || \
        fail "evidence_commit must be a non-merge artifact-producer commit: $commit"
    produced=$(git -C "$repository_root" diff-tree --root --diff-filter=A --no-commit-id --name-only -r "$commit" -- "$@") || \
        fail "cannot inspect produced artifacts at evidence_commit: $commit"
    while IFS= read -r produced_path; do
        [[ -n "$produced_path" ]] && produced_count=$((produced_count + 1))
    done <<< "$produced"
    [[ "$produced_count" -eq "$expected_count" ]] || \
        fail "evidence_commit did not produce artifact bundle: $commit"
}

awk -F '\t' -v expected_surfaces="$EXPECTED_SURFACES" -v expected_visual="$EXPECTED_VISUAL_CASES" '
function invalid(message) {
    print message > "/dev/stderr"
    bad = 1
}
function token(value) { return value ~ /^[a-z0-9][a-z0-9.-]*$/ }
function emit_case(id, group, state, appearance, device, locale, content_size, key) {
    key = id "\t" state "\t" appearance "\t" device "\t" locale "\t" content_size
    if (seen_case[key]++) { invalid("duplicate expanded requirement case " key); return }
    print key "\t" group "--" state "\tvisual-ready." group "." state
    visual_count++
}
BEGIN { expected_header = "surface_id\tcase_group\tstates\tappearances\tdevices\tlocales\tcontent_sizes\tfocused_cases\tpolicy" }
/^#/ || NF == 0 { next }
header == 0 {
    if ($0 != expected_header) { invalid("unexpected requirements header"); exit 65 }
    header = 1
    next
}
{
    id = $1
    if (NF != 9) invalid("requirements row must have 9 fields at " id)
    if (id !~ /^[0-9][0-9]$/) invalid("invalid surface id " id)
    if (seen_id[id]++) invalid("duplicate surface id " id)
    if (!token($2)) invalid("invalid case group at " id)
    if ((id == "34" && $9 != "deferred") || (id == "43" && $9 != "route-audit") || (id != "34" && id != "43" && $9 != "visual")) {
        invalid("surface policy mismatch at " id)
    }

    state_count = split($3, states, "|")
    appearance_count = split($4, appearances, "|")
    device_count = split($5, devices, "|")
    locale_count = split($6, locales, "|")
    content_count = split($7, content_sizes, "|")
    delete seen_state
    delete seen_appearance
    delete seen_device
    delete seen_locale
    delete seen_content
    for (i = 1; i <= state_count; i++) if (!token(states[i]) || seen_state[states[i]]++) invalid("invalid or duplicate state at " id)
    for (i = 1; i <= appearance_count; i++) if (!token(appearances[i]) || seen_appearance[appearances[i]]++) invalid("invalid or duplicate appearance at " id)
    for (i = 1; i <= device_count; i++) if (!token(devices[i]) || seen_device[devices[i]]++) invalid("invalid or duplicate device at " id)
    for (i = 1; i <= locale_count; i++) if (!token(locales[i]) || seen_locale[locales[i]]++) invalid("invalid or duplicate locale at " id)
    for (i = 1; i <= content_count; i++) if (!token(content_sizes[i]) || seen_content[content_sizes[i]]++) invalid("invalid or duplicate content size at " id)

    if ($9 == "deferred") {
        if (id != "34" || $3 != "deferred" || $4 != "none" || $5 != "none" || $6 != "none" || $7 != "none" || $8 != "none") {
            invalid("surface 34 deferred axes must be exact")
        }
        deferred_count++
        next
    }
    if ($9 == "route-audit") {
        if (id != "43" || $3 != "ordinary-route-absent" || $4 != "none" || $5 != "none" || $6 != "none" || $7 != "none" || $8 != "none") {
            invalid("surface 43 route-audit axes must be exact")
        }
        print id "\t" states[1] "\tnone\tnone\tnone\tnone\t" $2 "--" states[1] "\tvisual-ready." $2 "." states[1]
        route_count++
        next
    }
    if ($3 ~ /(^|\|)none(\||$)/ || $4 ~ /(^|\|)none(\||$)/ || $5 ~ /(^|\|)none(\||$)/ || $6 ~ /(^|\|)none(\||$)/ || $7 ~ /(^|\|)none(\||$)/) {
        invalid("visual case cannot use none axes at " id)
    }
    for (i = 1; i <= state_count; i++)
        for (j = 1; j <= appearance_count; j++)
            for (k = 1; k <= device_count; k++)
                for (l = 1; l <= locale_count; l++)
                    for (m = 1; m <= content_count; m++)
                        emit_case(id, $2, states[i], appearances[j], devices[k], locales[l], content_sizes[m])

    if ($8 != "none") {
        focused_count = split($8, focused, "|")
        for (i = 1; i <= focused_count; i++) {
            part_count = split(focused[i], parts, "@")
            if (part_count != 5) { invalid("focused case must have five axes at " id); continue }
            valid = 1
            for (j = 1; j <= 5; j++) if (!token(parts[j]) || parts[j] == "none") valid = 0
            if (!valid) { invalid("invalid focused case at " id); continue }
            emit_case(id, $2, parts[1], parts[2], parts[3], parts[4], parts[5])
        }
    }
}
END {
    if (!header) invalid("missing requirements header")
    if (length(seen_id) != expected_surfaces) invalid("expected 45 requirement rows, found " length(seen_id))
    if (route_count != 1) invalid("exactly one route-audit row is required")
    if (deferred_count != 1) invalid("exactly one deferred row is required")
    if (visual_count != expected_visual) invalid("expected " expected_visual " visual cases, found " visual_count)
    if (bad) exit 65
}
' "$requirements" > "$expanded_all" || fail "invalid canonical requirement matrix"

actual_requirements_sha=$(sha256_file "$requirements")
[[ "$actual_requirements_sha" == "$EXPECTED_REQUIREMENTS_SHA256" ]] || \
    fail "requirements contract digest mismatch (contract shrink or unpinned edit)"

awk -F '\t' '$3 != "none" { print }' "$expanded_all" | LC_ALL=C sort > "$expected_cases"
cut -f 1-6 "$expected_cases" > "$expected_keys"
awk -F '\t' '$3 == "none" { print $1 "\t" $2 }' "$expanded_all" > "$route_audits"

awk -F '\t' '/^#/ || NF == 0 { next } $1 == "id" { next } { print $1 }' \
    "$ledger" | LC_ALL=C sort > "$ledger_ids"
awk -F '\t' '/^#/ || NF == 0 { next } $1 == "surface_id" { next } { print $1 }' \
    "$requirements" | LC_ALL=C sort > "$requirement_ids"
/usr/bin/cmp -s "$ledger_ids" "$requirement_ids" || \
    fail "requirement IDs do not exactly match the 45-surface ledger"

awk -F '\t' '
BEGIN { expected_header = "surface_id\tstate\tappearance\tdevice\tfixture\tlocale\tcontent_size\tvisual_ready\tbaseline\tcandidate\tdiff_dir\treview_record\tevidence_commit" }
/^#/ || NF == 0 { next }
header == 0 {
    if ($0 != expected_header) { print "unexpected evidence header" > "/dev/stderr"; exit 65 }
    header = 1
    next
}
{
    if (NF != 13) { print "evidence row must have 13 fields at line " NR > "/dev/stderr"; bad = 1 }
    key = $1 "\t" $2 "\t" $3 "\t" $4 "\t" $6 "\t" $7
    if (seen[key]++) { print "duplicate evidence key " key > "/dev/stderr"; bad = 1 }
    print key
}
END {
    if (!header) { print "missing evidence header" > "/dev/stderr"; bad = 1 }
    if (bad) exit 65
}
' "$evidence" | LC_ALL=C sort > "$recorded_cases" || fail "invalid evidence manifest schema"

unexpected="${temporary_dir}/unexpected.txt"
/usr/bin/comm -13 "$expected_keys" "$recorded_cases" > "$unexpected"
[[ ! -s "$unexpected" ]] || fail "unexpected evidence case: $(head -n 1 "$unexpected" | tr '\t' '/')"

missing="${temporary_dir}/missing.txt"
/usr/bin/comm -23 "$expected_keys" "$recorded_cases" > "$missing"
expected_count=$(wc -l < "$expected_keys" | tr -d ' ')
recorded_count=$(wc -l < "$recorded_cases" | tr -d ' ')
missing_count=$(wc -l < "$missing" | tr -d ' ')
[[ "$expected_count" -eq "$EXPECTED_VISUAL_CASES" ]] || fail "expanded case count is not pinned total"

awk -F '\t' '
BEGIN { expected_header = "device\tmask_path\tsha256\tmax_ignored_pixels\tallowed_x\tallowed_y\tallowed_width\tallowed_height" }
/^#/ || NF == 0 { next }
header == 0 {
    if ($0 != expected_header) { print "unexpected mask policy header" > "/dev/stderr"; exit 65 }
    header = 1
    next
}
{
    key = $1 "\t" $2
    if (NF != 8 || seen[key]++) { print "invalid or duplicate mask policy row" > "/dev/stderr"; bad = 1 }
    if ($1 !~ /^[a-z0-9][a-z0-9.-]*$/ || $2 !~ /^artifacts\/visual-acceptance\/masks\/[A-Za-z0-9._-]+[.]png$/ || $3 !~ /^[0-9a-f]{64}$/) bad = 1
    for (i = 4; i <= 8; i++) if ($i !~ /^[0-9]+$/) bad = 1
    if ($4 < 1 || $7 < 1 || $8 < 1) bad = 1
}
END { if (!header || bad) exit 65 }
' "$mask_policy" || fail "invalid mask policy contract"

awk -F '\t' '
BEGIN { expected_header = "device\torientation\tpixel_width\tpixel_height" }
/^#/ || NF == 0 { next }
header == 0 {
    if ($0 != expected_header) { print "unexpected capture policy header" > "/dev/stderr"; exit 65 }
    header = 1
    next
}
{
    if (NF != 4 || seen[$1]++) { print "invalid or duplicate capture policy row" > "/dev/stderr"; bad = 1 }
    if ($1 !~ /^[a-z0-9][a-z0-9.-]*$/ || ($2 != "portrait" && $2 != "landscape")) bad = 1
    if ($3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ || $3 < 1 || $4 < 1) bad = 1
    if (($2 == "portrait" && $3 >= $4) || ($2 == "landscape" && $3 <= $4)) bad = 1
    rows++
}
END { if (!header || rows != 2 || bad) exit 65 }
' "$capture_policy" || fail "invalid capture policy contract"
[[ "$(sha256_file "$capture_policy")" == "$EXPECTED_CAPTURE_POLICY_SHA256" ]] || \
    fail "capture policy does not match the authoritative device profile"

approval_row=$(awk -F '\t' '
BEGIN { expected_header = "policy_sha256\tpolicy_commit" }
/^#/ || NF == 0 { next }
header == 0 {
    if ($0 != expected_header) exit 65
    header = 1
    next
}
{
    if (NF != 2 || rows++) exit 65
    if ($1 !~ /^[0-9a-f]{64}$/ || $2 !~ /^[0-9a-f]{40}$/) exit 65
    print
}
END { if (!header || rows != 1) exit 65 }
' "$mask_policy_approval") || fail "invalid mask policy approval contract"
IFS=$'\t' read -r approved_policy_sha approved_policy_commit <<< "$approval_row"
[[ "$(sha256_file "$mask_policy")" == "$approved_policy_sha" ]] || fail "mask policy digest is not independently approved"
git -C "$repository_root" cat-file -e "${approved_policy_commit}^{commit}" 2>/dev/null || \
    fail "unknown approved mask policy commit: $approved_policy_commit"
git -C "$repository_root" merge-base --is-ancestor "$approved_policy_commit" HEAD || \
    fail "approved mask policy commit is not an ancestor of HEAD"
mask_policy_relative="${mask_policy#${repository_root}/}"
mask_policy_path=$(canonical_existing_file "$mask_policy_relative" mask-policy)
approved_policy_blob=$(git_blob_at "$approved_policy_commit" "$mask_policy_relative") || \
    fail "mask policy was not tracked at its approved commit"
[[ "$approved_policy_blob" == "$(git -C "$repository_root" hash-object "$mask_policy_path")" ]] || \
    fail "approved mask policy commit does not pin the current policy"
mask_policy_approval_relative="${mask_policy_approval#${repository_root}/}"
mask_policy_approval_path=$(canonical_existing_file "$mask_policy_approval_relative" mask-policy-approval)
capture_policy_relative="${capture_policy#${repository_root}/}"
capture_policy_path=$(canonical_existing_file "$capture_policy_relative" capture-policy)

while IFS=$'\t' read -r surface state appearance device fixture locale content_size visual_ready baseline candidate diff_dir review_record commit; do
    [[ "$surface" == "surface_id" || "$surface" == \#* || -z "$surface" ]] && continue
    [[ "$surface" =~ ^[0-9][0-9]$ ]] || fail "invalid evidence surface ID: $surface"
    for token in "$state" "$appearance" "$device" "$fixture" "$locale" "$content_size" "$visual_ready"; do
        [[ "$token" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid evidence metadata token at $surface/$state"
    done

    expected_row=$(awk -F '\t' -v id="$surface" -v state="$state" -v appearance="$appearance" -v device="$device" -v locale="$locale" -v content="$content_size" \
        '$1 == id && $2 == state && $3 == appearance && $4 == device && $5 == locale && $6 == content { print; exit }' "$expected_cases")
    [[ -n "$expected_row" ]] || fail "unexpected evidence metadata: $surface/$state/$appearance/$device/$locale/$content_size"
    expected_fixture=$(printf '%s\n' "$expected_row" | cut -f 7)
    expected_ready=$(printf '%s\n' "$expected_row" | cut -f 8)
    [[ "$fixture" == "$expected_fixture" ]] || fail "fixture metadata mismatch: $surface/$state/$appearance/$device"
    [[ "$visual_ready" == "$expected_ready" ]] || fail "visualReady metadata mismatch: $surface/$state/$appearance/$device"
    capture_policy_row=$(awk -F '\t' -v device="$device" '$1 == device { print; exit }' "$capture_policy")
    [[ -n "$capture_policy_row" ]] || fail "missing capture policy for device: $device"
    capture_orientation=$(printf '%s\n' "$capture_policy_row" | cut -f 2)
    capture_width=$(printf '%s\n' "$capture_policy_row" | cut -f 3)
    capture_height=$(printf '%s\n' "$capture_policy_row" | cut -f 4)

    case_id="${surface}--${state}--${appearance}--${device}--${locale}--${content_size}"
    case_root="artifacts/visual-acceptance/cases/${case_id}"
    expected_baseline="${case_root}/baseline.png"
    expected_candidate="${case_root}/candidate.png"
    expected_diff="${case_root}/diff"
    expected_review="${case_root}/review.json"
    [[ "$baseline" != "$candidate" ]] || fail "baseline and candidate paths must differ for $case_id"
    [[ "$baseline" == "$expected_baseline" ]] || fail "non-canonical baseline path for $case_id"
    [[ "$candidate" == "$expected_candidate" ]] || fail "non-canonical candidate path for $case_id"
    [[ "$diff_dir" == "$expected_diff" ]] || fail "non-canonical diff path for $case_id"
    [[ "$review_record" == "$expected_review" ]] || fail "non-canonical review path for $case_id"
    register_unique_path "$baseline" baseline
    register_unique_path "$candidate" candidate
    register_unique_path "$diff_dir" diff
    register_unique_path "$review_record" review

    baseline_path=$(canonical_existing_file "$baseline" baseline)
    candidate_path=$(canonical_existing_file "$candidate" candidate)
    diff_path=$(canonical_existing_directory "$diff_dir" diff)
    review_path=$(canonical_existing_file "$review_record" review-record)
    summary_relative="${diff_dir}/summary.json"
    heatmap_relative="${diff_dir}/diff-heatmap.png"
    side_by_side_relative="${diff_dir}/side-by-side.png"
    overlay_relative="${diff_dir}/overlay.png"
    summary_path=$(canonical_existing_file "$summary_relative" summary)
    heatmap_path=$(canonical_existing_file "$heatmap_relative" heatmap)
    side_by_side_path=$(canonical_existing_file "$side_by_side_relative" side-by-side)
    overlay_path=$(canonical_existing_file "$overlay_relative" overlay)
    [[ "$summary_path" == "$diff_path/summary.json" && "$heatmap_path" == "$diff_path/diff-heatmap.png" && \
       "$side_by_side_path" == "$diff_path/side-by-side.png" && "$overlay_path" == "$diff_path/overlay.png" ]] || \
        fail "diff artifact aliases canonical directory for $case_id"

    read -r baseline_width baseline_height <<< "$(image_dimensions "$baseline_path")"
    read -r candidate_width candidate_height <<< "$(image_dimensions "$candidate_path")"
    [[ "$baseline_width" -eq "$candidate_width" && "$baseline_height" -eq "$candidate_height" ]] || \
        fail "baseline/candidate dimensions differ for $case_id"
    [[ "$baseline_width" -eq "$capture_width" && "$baseline_height" -eq "$capture_height" ]] || \
        fail "capture dimensions or orientation violate device policy for $case_id: expected ${capture_orientation} ${capture_width}x${capture_height}, received ${baseline_width}x${baseline_height}"
    read -r heatmap_width heatmap_height <<< "$(image_dimensions "$heatmap_path")"
    read -r side_width side_height <<< "$(image_dimensions "$side_by_side_path")"
    read -r overlay_width overlay_height <<< "$(image_dimensions "$overlay_path")"
    [[ "$heatmap_width" -eq "$baseline_width" && "$heatmap_height" -eq "$baseline_height" ]] || fail "heatmap dimensions mismatch for $case_id"
    [[ "$side_width" -eq $((baseline_width * 2)) && "$side_height" -eq "$baseline_height" ]] || fail "side-by-side dimensions mismatch for $case_id"
    [[ "$overlay_width" -eq "$baseline_width" && "$overlay_height" -eq "$baseline_height" ]] || fail "overlay dimensions mismatch for $case_id"

    baseline_sha=$(sha256_file "$baseline_path")
    candidate_sha=$(sha256_file "$candidate_path")
    register_unique_image_content "$baseline_sha" "$used_baseline_hashes" baseline "$case_id"
    register_unique_image_content "$candidate_sha" "$used_candidate_hashes" candidate "$case_id"
    baseline_pixel_digest=$(canonical_pixel_digest \
        "$baseline_path" "$capture_orientation" "$baseline_width" "$baseline_height")
    candidate_pixel_digest=$(canonical_pixel_digest \
        "$candidate_path" "$capture_orientation" "$candidate_width" "$candidate_height")
    register_canonical_pixel_content "$baseline_pixel_digest" "$case_id" baseline
    register_canonical_pixel_content "$candidate_pixel_digest" "$case_id" candidate
    summary_result=$("$json_validator" summary "$summary_path" \
        "$surface" "$state" "$appearance" "$device" "$capture_orientation" "$fixture" "$locale" "$content_size" "$visual_ready" \
        "$baseline" "$candidate" "$summary_relative" "$heatmap_relative" "$side_by_side_relative" "$overlay_relative" \
        "$baseline_sha" "$candidate_sha" "$baseline_width" "$baseline_height" "$candidate_width" "$candidate_height" \
        "$SUMMARY_SCHEMA_VERSION") || fail "strict summary validation failed for $case_id"

    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || fail "evidence_commit must be a full lowercase commit hash for $case_id"
    git -C "$repository_root" cat-file -e "${commit}^{commit}" 2>/dev/null || fail "unknown evidence_commit: $commit"
    git -C "$repository_root" merge-base --is-ancestor "$commit" HEAD || fail "evidence_commit is not an ancestor of HEAD: $commit"
    [[ "$approved_policy_commit" != "$commit" ]] || fail "mask policy approval must predate evidence_commit: $commit"
    git -C "$repository_root" merge-base --is-ancestor "$approved_policy_commit" "$commit" || \
        fail "mask policy approval does not predate evidence_commit: $commit"
    require_prior_immutable_blob "$mask_policy_relative" "$commit" mask-policy "$mask_policy_path"
    require_prior_immutable_blob "$mask_policy_approval_relative" "$commit" mask-policy-approval "$mask_policy_approval_path"
    require_prior_immutable_blob "$capture_policy_relative" "$commit" capture-policy "$capture_policy_path"

    IFS=$'\t' read -r summary_marker fuzz_percent channel_delta max_changed_ratio min_ssim max_normalized_rmse \
        mask_requested mask_relative mask_sha ignored_pixels ignored_x ignored_y ignored_width ignored_height <<< "$summary_result"
    [[ "$summary_marker" == "summary" ]] || fail "invalid summary validator output for $case_id"
    if [[ "$mask_requested" == "true" ]]; then
        [[ -x "$magick_bin" ]] || fail "ImageMagick is required to audit masks: $magick_bin"
        policy_row=$(awk -F '\t' -v device="$device" -v path="$mask_relative" '$1 == device && $2 == path { print; exit }' "$mask_policy")
        [[ -n "$policy_row" ]] || fail "unapproved mask for $case_id: $mask_relative"
        policy_sha=$(printf '%s\n' "$policy_row" | cut -f 3)
        max_ignored=$(printf '%s\n' "$policy_row" | cut -f 4)
        allowed_x=$(printf '%s\n' "$policy_row" | cut -f 5)
        allowed_y=$(printf '%s\n' "$policy_row" | cut -f 6)
        allowed_width=$(printf '%s\n' "$policy_row" | cut -f 7)
        allowed_height=$(printf '%s\n' "$policy_row" | cut -f 8)
        [[ "$mask_sha" == "$policy_sha" ]] || fail "mask hash is not approved for $case_id"
        mask_path=$(canonical_existing_file "$mask_relative" mask)
        [[ "$(sha256_file "$mask_path")" == "$mask_sha" ]] || fail "mask file hash drift for $case_id"
        approved_mask_blob=$(git_blob_at "$approved_policy_commit" "$mask_relative") || \
            fail "mask was not pinned at the approved policy commit for $case_id"
        [[ "$approved_mask_blob" == "$(git -C "$repository_root" hash-object "$mask_path")" ]] || \
            fail "mask differs from the independently approved policy commit for $case_id"
        read -r mask_width mask_height <<< "$(image_dimensions "$mask_path")"
        [[ "$mask_width" -eq "$baseline_width" && "$mask_height" -eq "$baseline_height" ]] || fail "mask dimensions mismatch for $case_id"
        require_immutable_blob "$mask_relative" "$commit" mask "$mask_path"
        effective_mask="${temporary_dir}/effective-mask.png"
        ignored_mask="${temporary_dir}/ignored-mask.png"
        "$magick_bin" "$mask_path" -alpha off -colorspace Gray -threshold 50% "$effective_mask"
        compared_output=$("$magick_bin" -precision 20 "$effective_mask" -format '%[fx:round(w*h*mean)]' info:)
        [[ "$compared_output" =~ ^[0-9]+$ ]] || fail "cannot count approved mask pixels for $case_id"
        actual_ignored=$((baseline_width * baseline_height - compared_output))
        "$magick_bin" "$effective_mask" -negate "$ignored_mask"
        ignored_geometry=$("$magick_bin" "$ignored_mask" -bordercolor black -border 1 -trim -format '%wx%h%O' info:)
        [[ "$ignored_geometry" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]] || fail "cannot inspect mask bounds for $case_id"
        actual_width="${BASH_REMATCH[1]}"
        actual_height="${BASH_REMATCH[2]}"
        actual_x=$((BASH_REMATCH[3] - 1))
        actual_y=$((BASH_REMATCH[4] - 1))
        [[ "$actual_ignored" -eq "$ignored_pixels" && "$actual_x" -eq "$ignored_x" && "$actual_y" -eq "$ignored_y" && \
           "$actual_width" -eq "$ignored_width" && "$actual_height" -eq "$ignored_height" ]] || fail "summary mask metrics mismatch for $case_id"
        [[ "$actual_ignored" -le "$max_ignored" ]] || fail "mask ignores too many pixels for $case_id"
        [[ "$actual_x" -ge "$allowed_x" && "$actual_y" -ge "$allowed_y" && \
           $((actual_x + actual_width)) -le $((allowed_x + allowed_width)) && \
           $((actual_y + actual_height)) -le $((allowed_y + allowed_height)) ]] || fail "mask exceeds approved minimal bounds for $case_id"
    elif [[ "$mask_requested" != "false" ]]; then
        fail "invalid mask request state for $case_id"
    fi

    recomputed_dir="${temporary_dir}/recomputed"
    recompute_arguments=(
        --magick "$magick_bin"
        --surface-id "$surface"
        --state "$state"
        --appearance "$appearance"
        --device "$device"
        --orientation "$capture_orientation"
        --fixture "$fixture"
        --locale "$locale"
        --content-size "$content_size"
        --visual-ready "$visual_ready"
        --fuzz "${fuzz_percent}%"
        --channel-delta "$channel_delta"
        --threshold "$max_changed_ratio"
        --min-ssim "$min_ssim"
        --out "$recomputed_dir"
    )
    if [[ "$max_normalized_rmse" != "none" ]]; then
        recompute_arguments+=(--max-rmse "$max_normalized_rmse")
    fi
    if [[ "$mask_requested" == "true" ]]; then
        recompute_arguments+=(--mask "$mask_path")
    fi
    "$comparator" "${recompute_arguments[@]}" "$baseline_path" "$candidate_path" >/dev/null || \
        fail "independent pixel recomputation did not pass for $case_id"
    "$json_validator" recomputed "$summary_path" "$recomputed_dir/summary.json" >/dev/null || \
        fail "independent pixel recomputation metrics mismatch for $case_id"
    [[ "$(sha256_file "$heatmap_path")" == "$(sha256_file "$recomputed_dir/diff-heatmap.png")" ]] || \
        fail "independent pixel recomputation heatmap mismatch for $case_id"
    [[ "$(sha256_file "$side_by_side_path")" == "$(sha256_file "$recomputed_dir/side-by-side.png")" ]] || \
        fail "independent pixel recomputation side-by-side mismatch for $case_id"
    [[ "$(sha256_file "$overlay_path")" == "$(sha256_file "$recomputed_dir/overlay.png")" ]] || \
        fail "independent pixel recomputation overlay mismatch for $case_id"

    require_immutable_blob "$baseline" "$commit" baseline "$baseline_path"
    require_immutable_blob "$candidate" "$commit" candidate "$candidate_path"
    require_immutable_blob "$summary_relative" "$commit" summary "$summary_path"
    require_immutable_blob "$heatmap_relative" "$commit" heatmap "$heatmap_path"
    require_immutable_blob "$side_by_side_relative" "$commit" side-by-side "$side_by_side_path"
    require_immutable_blob "$overlay_relative" "$commit" overlay "$overlay_path"
    require_artifact_producer "$commit" "$baseline" "$candidate" "$summary_relative" \
        "$heatmap_relative" "$side_by_side_relative" "$overlay_relative"

    if git -C "$repository_root" cat-file -e "${commit}:${review_record}" 2>/dev/null; then
        fail "review record must be produced after evidence_commit: $review_record"
    fi
    review_commits=$(git -C "$repository_root" log --diff-filter=A --format=%H -- "$review_record")
    review_count=$(printf '%s\n' "$review_commits" | awk 'NF { count++ } END { print count + 0 }')
    [[ "$review_count" -eq 1 ]] || fail "review record must be added exactly once: $review_record"
    review_commit=$(printf '%s\n' "$review_commits" | awk 'NF { value=$0 } END { print value }')
    [[ "$review_commit" != "$commit" ]] || fail "review record cannot self-reference its artifact commit"
    git -C "$repository_root" merge-base --is-ancestor "$commit" "$review_commit" || fail "review record does not descend from evidence_commit"
    git -C "$repository_root" merge-base --is-ancestor "$review_commit" HEAD || fail "review record commit is not an ancestor of HEAD"
    review_intro_blob=$(git_blob_at "$review_commit" "$review_record") || fail "review record missing from its introduction commit"
    review_head_blob=$(git_blob_at HEAD "$review_record") || fail "review record is not tracked at HEAD"
    review_current_blob=$(git -C "$repository_root" hash-object "$review_path")
    [[ "$review_intro_blob" == "$review_head_blob" && "$review_head_blob" == "$review_current_blob" ]] || fail "review record is mutable or drifted: $review_record"
    overlay_sha=$(sha256_file "$overlay_path")
    "$json_validator" review "$review_path" "$surface" "$state" "$appearance" "$device" "$fixture" "$locale" "$content_size" "$visual_ready" \
        "$commit" "$overlay_sha" "$REVIEW_SCHEMA_VERSION" >/dev/null || fail "strict review record validation failed for $case_id"
done < "$evidence"

if [[ "$mode" == "--require-complete" ]]; then
    [[ "$missing_count" -eq 0 ]] || fail "missing ${missing_count}/${expected_count} visual evidence cases (first: $(head -n 1 "$missing" | tr '\t' '/'))"
    for surface in $(seq -w 1 "$EXPECTED_SURFACES"); do
        [[ "$surface" == "34" ]] && continue
        awk -F '\t' -v id="$surface" '
            $1 == id {
                found = 1
                if ($4 != "swiftui" || $5 != "accepted") exit 1
            }
            END { if (!found) exit 1 }
        ' "$ledger" || fail "surface is not SwiftUI accepted in route ledger: $surface"
    done
fi

route_count=$(wc -l < "$route_audits" | tr -d ' ')
deferred_count=$(awk -F '\t' '$9 == "deferred" { count++ } END { print count + 0 }' "$requirements")
printf 'visual acceptance inventory valid: surfaces=%s visual_cases=%s recorded=%s missing=%s route_audits=%s deferred=%s requirements_sha256=%s mode=%s\n' \
    "$EXPECTED_SURFACES" "$expected_count" "$recorded_count" "$missing_count" "$route_count" "$deferred_count" "$actual_requirements_sha" "$mode"
