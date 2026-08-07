#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_dir}/.." && pwd)"
ledger="${repository_root}/docs/ui-migration-surfaces.tsv"
format="${1:---markdown}"

case "${format}" in
    --markdown|--json) ;;
    *)
        echo "usage: $0 [--markdown|--json]" >&2
        exit 64
        ;;
esac

if [[ ! -f "${ledger}" ]]; then
    echo "missing migration ledger: ${ledger}" >&2
    exit 66
fi

awk -F '\t' -v format="${format}" '
function fail(message) {
    print "invalid migration ledger: " message > "/dev/stderr"
    invalid = 1
}

BEGIN {
    expected_total = 45
}

/^#/ || NF == 0 { next }

$1 == "id" {
    if ($2 != "area" || $3 != "surface" || $4 != "runtime_owner" || $5 != "migration_state") {
        fail("unexpected header")
    }
    next
}

{
    total++

    if ($1 !~ /^[0-9][0-9]$/) fail("id must be two digits at row " NR)
    if (seen[$1]++) fail("duplicate id " $1)
    if ($4 != "swiftui" && $4 != "uikit" && $4 != "none") fail("unknown runtime_owner " $4 " at id " $1)
    if ($5 != "accepted" && $5 != "migrating" && $5 != "legacy" && $5 != "deferred") {
        fail("unknown migration_state " $5 " at id " $1)
    }
    if ($5 == "accepted" && $4 != "swiftui") fail("accepted surface must be SwiftUI at id " $1)
    if (($5 == "deferred") != ($4 == "none")) fail("deferred surface must have no runtime owner at id " $1)
    if ($6 == "") fail("missing evidence at id " $1)

    owner[$4]++
    state[$5]++
}

END {
    if (total != expected_total) fail("expected " expected_total " surfaces, found " total)
    for (id = 1; id <= expected_total; id++) {
        key = sprintf("%02d", id)
        if (!seen[key]) fail("missing id " key)
    }
    if (invalid) exit 65

    swiftui = owner["swiftui"] + 0
    uikit = owner["uikit"] + 0
    none = owner["none"] + 0
    accepted = state["accepted"] + 0
    migrating = state["migrating"] + 0
    legacy = state["legacy"] + 0
    deferred = state["deferred"] + 0
    swiftui_percent = 100 * swiftui / total
    uikit_percent = 100 * uikit / total
    none_percent = 100 * none / total
    accepted_percent = 100 * accepted / total
    migrating_percent = 100 * migrating / total
    legacy_percent = 100 * legacy / total
    deferred_percent = 100 * deferred / total

    if (format == "--json") {
        printf "{\n"
        printf "  \"total_surfaces\": %d,\n", total
        printf "  \"runtime\": {\"swiftui\": %d, \"swiftui_percent\": %.1f, \"uikit\": %d, \"uikit_percent\": %.1f, \"none\": %d, \"none_percent\": %.1f},\n", swiftui, swiftui_percent, uikit, uikit_percent, none, none_percent
        printf "  \"acceptance\": {\"accepted\": %d, \"accepted_percent\": %.1f, \"migrating\": %d, \"migrating_percent\": %.1f, \"legacy\": %d, \"legacy_percent\": %.1f, \"deferred\": %d, \"deferred_percent\": %.1f}\n", accepted, accepted_percent, migrating, migrating_percent, legacy, legacy_percent, deferred, deferred_percent
        printf "}\n"
    } else {
        print "# UIKit / SwiftUI migration progress"
        print ""
        printf "- Primary progress: SwiftUI %d/%d (%.1f%%)\n", swiftui, total, swiftui_percent
        printf "- Remaining UIKit: %d/%d (%.1f%%)\n", uikit, total, uikit_percent
        printf "- Deferred runtime: %d/%d (%.1f%%)\n", none, total, none_percent
        printf "- Accepted surfaces: %d/%d (%.1f%%)\n", accepted, total, accepted_percent
        printf "- Migrating surfaces: %d/%d (%.1f%%)\n", migrating, total, migrating_percent
        printf "- Legacy surfaces: %d/%d (%.1f%%)\n", legacy, total, legacy_percent
        printf "- Deferred surfaces: %d/%d (%.1f%%)\n", deferred, total, deferred_percent
    }
}
' "${ledger}"
