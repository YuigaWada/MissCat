#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repository_root="$(cd "${script_dir}/.." && pwd -P)"
requirements="${repository_root}/docs/visual-acceptance-requirements.tsv"
evidence="${repository_root}/docs/visual-acceptance-evidence.tsv"
ledger="${repository_root}/docs/ui-migration-surfaces.tsv"
mode="--inventory"

usage() {
    cat >&2 <<'USAGE'
usage: scripts/verify-visual-acceptance.sh [--inventory|--require-complete]
       [--requirements PATH] [--evidence PATH] [--ledger PATH]

--inventory validates the complete 45-surface requirement inventory and any
evidence already recorded. --require-complete additionally rejects every
missing visual case and an unaccepted route-audit surface.
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

[[ -f "$requirements" ]] || fail "missing requirements: $requirements"
[[ -f "$evidence" ]] || fail "missing evidence manifest: $evidence"
[[ -f "$ledger" ]] || fail "missing migration ledger: $ledger"

temporary_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/misscat-visual-acceptance.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT
expected_cases="${temporary_dir}/expected.tsv"
route_audits="${temporary_dir}/route-audits.tsv"
recorded_cases="${temporary_dir}/recorded.tsv"
ledger_ids="${temporary_dir}/ledger-ids.txt"
requirement_ids="${temporary_dir}/requirement-ids.txt"

awk -F '\t' '
BEGIN { expected_header = "surface_id\tcase_group\tstates\tappearances\tdevices\tpolicy" }
/^#/ || NF == 0 { next }
header == 0 {
    if ($0 != expected_header) {
        print "unexpected requirements header" > "/dev/stderr"
        exit 65
    }
    header = 1
    next
}
{
    id = $1
    if (NF != 6) { print "requirements row must have 6 fields at " id > "/dev/stderr"; bad = 1 }
    if (id !~ /^[0-9][0-9]$/) { print "invalid surface id " id > "/dev/stderr"; bad = 1 }
    if (seen_id[id]++) { print "duplicate surface id " id > "/dev/stderr"; bad = 1 }
    if ($2 !~ /^[a-z0-9][a-z0-9-]*$/) { print "invalid case group at " id > "/dev/stderr"; bad = 1 }
    if ($6 != "visual" && $6 != "route-audit") { print "invalid policy at " id > "/dev/stderr"; bad = 1 }

    state_count = split($3, states, "|")
    appearance_count = split($4, appearances, "|")
    device_count = split($5, devices, "|")
    delete seen_state
    delete seen_appearance
    delete seen_device
    for (i = 1; i <= state_count; i++) {
        if (states[i] !~ /^[a-z0-9][a-z0-9-]*$/ || seen_state[states[i]]++) {
            print "invalid or duplicate state at " id ": " states[i] > "/dev/stderr"; bad = 1
        }
    }
    for (i = 1; i <= appearance_count; i++) {
        if (appearances[i] !~ /^[a-z0-9][a-z0-9.-]*$/ || seen_appearance[appearances[i]]++) {
            print "invalid or duplicate appearance at " id ": " appearances[i] > "/dev/stderr"; bad = 1
        }
    }
    for (i = 1; i <= device_count; i++) {
        if (devices[i] !~ /^[a-z0-9][a-z0-9.-]*$/ || seen_device[devices[i]]++) {
            print "invalid or duplicate device at " id ": " devices[i] > "/dev/stderr"; bad = 1
        }
    }

    if ($6 == "route-audit") {
        if ($4 != "none" || $5 != "none") {
            print "route-audit must use none appearance/device at " id > "/dev/stderr"; bad = 1
        }
        print id "\t" states[1] "\tnone\tnone"
        route_count++
        next
    }
    if ($4 ~ /(^|\|)none(\||$)/ || $5 ~ /(^|\|)none(\||$)/) {
        print "visual case cannot use none appearance/device at " id > "/dev/stderr"; bad = 1
    }
    for (i = 1; i <= state_count; i++) {
        for (j = 1; j <= appearance_count; j++) {
            for (k = 1; k <= device_count; k++) {
                print id "\t" states[i] "\t" appearances[j] "\t" devices[k]
                visual_count++
            }
        }
    }
}
END {
    if (!header) { print "missing requirements header" > "/dev/stderr"; bad = 1 }
    if (length(seen_id) != 45) {
        print "expected 45 requirement rows, found " length(seen_id) > "/dev/stderr"; bad = 1
    }
    if (route_count < 1) { print "at least one route-audit row is required" > "/dev/stderr"; bad = 1 }
    if (visual_count < 44) { print "visual inventory is unexpectedly small" > "/dev/stderr"; bad = 1 }
    if (bad) exit 65
}
' "$requirements" > "${temporary_dir}/expanded-all.tsv"

awk -F '\t' '$3 != "none" && $4 != "none" { print }' "${temporary_dir}/expanded-all.tsv" | LC_ALL=C sort > "$expected_cases"
awk -F '\t' '$3 == "none" && $4 == "none" { print $1 "\t" $2 }' "${temporary_dir}/expanded-all.tsv" > "$route_audits"

awk -F '\t' '/^#/ || NF == 0 { next } $1 == "id" { next } { print $1 }' \
    "$ledger" | LC_ALL=C sort > "$ledger_ids"
awk -F '\t' '/^#/ || NF == 0 { next } $1 == "surface_id" { next } { print $1 }' \
    "$requirements" | LC_ALL=C sort > "$requirement_ids"
/usr/bin/cmp -s "$ledger_ids" "$requirement_ids" || fail "requirement IDs do not exactly match the 45-surface ledger"

awk -F '\t' '
BEGIN { expected_header = "surface_id\tstate\tappearance\tdevice\tbaseline\tcandidate\tdiff_dir\treviewer\tevidence_commit" }
/^#/ || NF == 0 { next }
header == 0 {
    if ($0 != expected_header) {
        print "unexpected evidence header" > "/dev/stderr"
        exit 65
    }
    header = 1
    next
}
{
    if (NF != 9) { print "evidence row must have 9 fields at line " NR > "/dev/stderr"; bad = 1 }
    key = $1 "\t" $2 "\t" $3 "\t" $4
    if (seen[key]++) { print "duplicate evidence key " key > "/dev/stderr"; bad = 1 }
    print key
}
END {
    if (!header) { print "missing evidence header" > "/dev/stderr"; bad = 1 }
    if (bad) exit 65
}
' "$evidence" | LC_ALL=C sort > "$recorded_cases"

unexpected="${temporary_dir}/unexpected.txt"
/usr/bin/comm -13 "$expected_cases" "$recorded_cases" > "$unexpected"
[[ ! -s "$unexpected" ]] || fail "unexpected evidence case: $(head -n 1 "$unexpected" | tr '\t' '/')"

missing="${temporary_dir}/missing.txt"
/usr/bin/comm -23 "$expected_cases" "$recorded_cases" > "$missing"
expected_count=$(wc -l < "$expected_cases" | tr -d ' ')
recorded_count=$(wc -l < "$recorded_cases" | tr -d ' ')
missing_count=$(wc -l < "$missing" | tr -d ' ')

is_safe_relative_path() {
    local path="$1"
    [[ -n "$path" && "$path" != /* && "$path" != ".." && "$path" != ../* && "$path" != */../* && "$path" != */.. ]]
}

sha256_file() {
    /usr/bin/openssl dgst -sha256 -r "$1" | awk '{ print $1 }'
}

json_value() {
    local path="$1"
    local key="$2"
    /usr/bin/plutil -extract "$key" raw -- "$path"
}

number_at_least() {
    awk -v actual="$1" -v minimum="$2" 'BEGIN { exit !(actual + 0 >= minimum + 0) }'
}

number_at_most() {
    awk -v actual="$1" -v maximum="$2" 'BEGIN { exit !(actual + 0 <= maximum + 0) }'
}

while IFS=$'\t' read -r surface state appearance device baseline candidate diff_dir reviewer commit; do
    [[ "$surface" == "surface_id" || "$surface" == \#* || -z "$surface" ]] && continue
    for path in "$baseline" "$candidate" "$diff_dir"; do
        is_safe_relative_path "$path" || fail "unsafe evidence path for $surface/$state/$appearance/$device: $path"
    done
    [[ "$reviewer" == "accepted" ]] || fail "reviewer has not accepted $surface/$state/$appearance/$device"
    [[ "$commit" =~ ^[0-9a-f]{7,40}$ ]] || fail "invalid evidence commit for $surface/$state/$appearance/$device"
    git -C "$repository_root" cat-file -e "${commit}^{commit}" 2>/dev/null || fail "unknown evidence commit: $commit"
    git -C "$repository_root" merge-base --is-ancestor "$commit" HEAD || fail "evidence commit is not an ancestor of HEAD: $commit"

    baseline_path="${repository_root}/${baseline}"
    candidate_path="${repository_root}/${candidate}"
    diff_path="${repository_root}/${diff_dir}"
    summary_path="${diff_path}/summary.json"
    [[ -f "$baseline_path" ]] || fail "missing baseline: $baseline"
    [[ -f "$candidate_path" ]] || fail "missing candidate: $candidate"
    for artifact in summary.json diff-heatmap.png side-by-side.png overlay.png; do
        [[ -f "${diff_path}/${artifact}" ]] || fail "missing diff artifact: ${diff_dir}/${artifact}"
    done
    /usr/bin/plutil -convert json -o /dev/null -- "$summary_path" || fail "invalid summary JSON: ${diff_dir}/summary.json"
    [[ "$(json_value "$summary_path" status)" == "passed" ]] || fail "comparison did not pass: $surface/$state/$appearance/$device"
    [[ "$(json_value "$summary_path" baseline.sha256)" == "$(sha256_file "$baseline_path")" ]] || fail "baseline hash drift: $baseline"
    [[ "$(json_value "$summary_path" candidate.sha256)" == "$(sha256_file "$candidate_path")" ]] || fail "candidate hash drift: $candidate"
    changed_similarity="$(json_value "$summary_path" comparison.changed_similarity)"
    ssim="$(json_value "$summary_path" comparison.ssim)"
    max_changed_ratio="$(json_value "$summary_path" comparison.max_changed_ratio)"
    min_ssim="$(json_value "$summary_path" comparison.min_ssim)"
    number_at_least "$changed_similarity" 0.90 || fail "changed-pixel similarity below 0.90: $surface/$state/$appearance/$device"
    number_at_least "$ssim" 0.90 || fail "SSIM below 0.90: $surface/$state/$appearance/$device"
    number_at_most "$max_changed_ratio" 0.10 || fail "comparison relaxed changed-pixel gate: $surface/$state/$appearance/$device"
    number_at_least "$min_ssim" 0.90 || fail "comparison relaxed SSIM gate: $surface/$state/$appearance/$device"
done < "$evidence"

if [[ "$mode" == "--require-complete" ]]; then
    [[ "$missing_count" -eq 0 ]] || fail "missing ${missing_count}/${expected_count} visual evidence cases (first: $(head -n 1 "$missing" | tr '\t' '/'))"
    while IFS=$'\t' read -r surface _state; do
        awk -F '\t' -v id="$surface" '
            $1 == id {
                found = 1
                if ($4 != "swiftui" || $5 != "accepted") exit 1
            }
            END { if (!found) exit 1 }
        ' "$ledger" || fail "route-audit surface is not SwiftUI accepted: $surface"
    done < "$route_audits"
fi

route_count=$(wc -l < "$route_audits" | tr -d ' ')
printf 'visual acceptance inventory valid: surfaces=45 visual_cases=%s recorded=%s missing=%s route_audits=%s mode=%s\n' \
    "$expected_count" "$recorded_count" "$missing_count" "$route_count" "$mode"
