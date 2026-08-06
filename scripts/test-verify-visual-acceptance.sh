#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repository_root="$(cd "${script_dir}/.." && pwd -P)"
readonly verifier="${script_dir}/verify-visual-acceptance.sh"
readonly comparator="${script_dir}/compare-screenshots.sh"
readonly magick_bin="${MAGICK_BIN:-/opt/homebrew/bin/magick}"

fail() {
    printf 'visual acceptance verifier self-test failed: %s\n' "$*" >&2
    exit 1
}

[[ -x "$verifier" ]] || fail "verifier is not executable"
[[ -x "$comparator" ]] || fail "comparator is not executable"
[[ -x "$magick_bin" ]] || fail "ImageMagick is unavailable: $magick_bin"

fixture_dir=$(/usr/bin/mktemp -d "${repository_root}/.visual-acceptance-test.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT
fixture_relative="${fixture_dir#${repository_root}/}"
requirements="${fixture_dir}/requirements.tsv"
evidence="${fixture_dir}/evidence.tsv"
ledger="${fixture_dir}/ledger.tsv"
baseline="${fixture_dir}/baseline.png"
candidate="${fixture_dir}/candidate.png"
diff_dir="${fixture_dir}/diff"

"$verifier" --inventory > "${fixture_dir}/repository-inventory.txt"
/usr/bin/grep -Fq 'surfaces=45' "${fixture_dir}/repository-inventory.txt" || fail "repository inventory did not validate all surfaces"

incomplete_status=0
"$verifier" --require-complete > /dev/null 2>&1 || incomplete_status=$?
[[ "$incomplete_status" -eq 1 ]] || fail "incomplete repository evidence must fail the complete gate"

printf '%s\n' 'surface_id	case_group	states	appearances	devices	policy' > "$requirements"
printf '%s\n' 'id	area	surface	runtime_owner	migration_state	evidence	note' > "$ledger"
for number in $(seq 1 45); do
    id=$(printf '%02d' "$number")
    if [[ "$id" == "43" ]]; then
        printf '%s\n' "${id}	retirement	ordinary-route-absent	none	none	route-audit" >> "$requirements"
    else
        printf '%s\n' "${id}	case-${id}	default	light	fixture-device	visual" >> "$requirements"
    fi
    printf '%s\n' "${id}	Fixture	Case ${id}	swiftui	accepted	fixture	test" >> "$ledger"
done

"$magick_bin" -size 4x4 xc:'#336699' "$baseline"
"$magick_bin" "$baseline" "$candidate"
"$comparator" --magick "$magick_bin" --out "$diff_dir" "$baseline" "$candidate" > /dev/null
commit=$(git -C "$repository_root" rev-parse HEAD)
printf '%s\n' 'surface_id	state	appearance	device	baseline	candidate	diff_dir	reviewer	evidence_commit' > "$evidence"
for number in $(seq 1 45); do
    id=$(printf '%02d' "$number")
    [[ "$id" == "43" ]] && continue
    printf '%s\n' "${id}	default	light	fixture-device	${fixture_relative}/baseline.png	${fixture_relative}/candidate.png	${fixture_relative}/diff	accepted	${commit}" >> "$evidence"
done

"$verifier" --require-complete --requirements "$requirements" --evidence "$evidence" --ledger "$ledger" \
    > "${fixture_dir}/complete.txt"
/usr/bin/grep -Fq 'missing=0' "${fixture_dir}/complete.txt" || fail "complete fixture did not report zero missing cases"

"$magick_bin" -size 4x4 xc:'#336698' "$candidate"
hash_status=0
"$verifier" --inventory --requirements "$requirements" --evidence "$evidence" --ledger "$ledger" \
    > /dev/null 2>&1 || hash_status=$?
[[ "$hash_status" -eq 1 ]] || fail "candidate hash drift must fail"
"$magick_bin" "$baseline" "$candidate"

/usr/bin/sed -i '' '2s/\taccepted\t/\tpending\t/' "$evidence"
review_status=0
"$verifier" --inventory --requirements "$requirements" --evidence "$evidence" --ledger "$ledger" \
    > /dev/null 2>&1 || review_status=$?
[[ "$review_status" -eq 1 ]] || fail "pending reviewer state must fail"

printf 'visual acceptance verifier self-test passed\n'
