#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
helper="$repo_root/scripts/misscat-auth-backup.sh"
app_source="$repo_root/MissCat/Others/App/MissCatApp.swift"

bash -n "$helper"

require_pattern() {
  pattern="$1"
  file="$2"
  rg -q --fixed-strings -- "$pattern" "$file" || {
    echo "missing backup safety contract: $pattern" >&2
    exit 1
  }
}

# Repeat operations accept only their per-launch nonce, never a stale result.
require_pattern '[ "$result_nonce" = "$expected_nonce" ]' "$helper"
require_pattern '--auth-backup-nonce "$nonce"' "$helper"
require_pattern '"nonce": nonce ?? "invalid"' "$app_source"

# Every operation explicitly removes and asserts all three simulator staging
# artifacts before reporting success. The EXIT trap remains a fallback.
require_pattern 'trap cleanup_on_exit EXIT' "$helper"
require_pattern 'rm -f -- "$sim_key" || cleanup_status=1' "$helper"
require_pattern 'rm -f -- "$sim_input" || cleanup_status=1' "$helper"
require_pattern 'rm -f -- "$sim_output" || cleanup_status=1' "$helper"
require_pattern 'assert_staging_absent || return 1' "$helper"
require_pattern 'finalize_operation export' "$helper"
require_pattern 'finalize_operation restore' "$helper"
require_pattern 'finalize_operation clear' "$helper"
require_pattern 'echo "$completed_operation succeeded"' "$helper"
require_pattern 'echo "$completed_operation staging cleanup failed" >&2' "$helper"

if rg -q --fixed-strings -- 'echo "$expected succeeded"' "$helper"; then
  echo "operation may report success before explicit staging cleanup" >&2
  exit 1
fi

# Exercise the actual helper cleanup/finalization functions. A successful
# finalization removes every artifact; a removal failure returns nonzero and
# never emits a success line.
contract_tmp="$(mktemp -d)"
cleanup_contract_fixture() {
  /bin/rm -f -- "$contract_tmp/key" "$contract_tmp/input" "$contract_tmp/output"
  /bin/rmdir "$contract_tmp" 2>/dev/null || true
}
trap cleanup_contract_fixture EXIT

helper_functions="$(
  sed -n '/^remove_staging_artifacts() {/,/^}/p' "$helper"
  sed -n '/^assert_staging_absent() {/,/^}/p' "$helper"
  sed -n '/^finalize_operation() {/,/^}/p' "$helper"
)"

: > "$contract_tmp/key"
: > "$contract_tmp/input"
: > "$contract_tmp/output"
success_output="$(
  HELPER_FUNCTIONS="$helper_functions" CONTRACT_TMP="$contract_tmp" bash -c '
    eval "$HELPER_FUNCTIONS"
    sim_key="$CONTRACT_TMP/key"
    sim_input="$CONTRACT_TMP/input"
    sim_output="$CONTRACT_TMP/output"
    finalize_operation export
  '
)"
[ "$success_output" = "export succeeded" ] || {
  echo "explicit staging cleanup success contract failed" >&2
  exit 1
}
for staged_path in "$contract_tmp/key" "$contract_tmp/input" "$contract_tmp/output"; do
  [ ! -e "$staged_path" ] && [ ! -L "$staged_path" ] || {
    echo "explicit staging absence assertion failed" >&2
    exit 1
  }
done

: > "$contract_tmp/output"
failure_output="$(
  HELPER_FUNCTIONS="$helper_functions" CONTRACT_TMP="$contract_tmp" bash -c '
    eval "$HELPER_FUNCTIONS"
    sim_key="$CONTRACT_TMP/key"
    sim_input="$CONTRACT_TMP/input"
    sim_output="$CONTRACT_TMP/output"
    rm() { return 1; }
    if finalize_operation restore; then exit 90; fi
  ' 2>&1
)"
case "$failure_output" in
  *"restore staging cleanup failed"*) ;;
  *) echo "cleanup failure contract was not reported" >&2; exit 1 ;;
esac
case "$failure_output" in
  *"restore succeeded"*) echo "cleanup failure reported success" >&2; exit 1 ;;
esac

# Clear requires secure host artifacts plus an app-side decryptability preflight.
require_pattern 'validate_secure_file "$key_path" "backup key" true' "$helper"
require_pattern 'validate_secure_file "$backup_path" "encrypted backup" true' "$helper"
require_pattern 'launch_operation preflight' "$helper"
require_pattern 'MissCatAuthenticationBackupClearPolicy.permitsClear' "$app_source"

# Host credential artifacts must be owned regular files, never symlinks, mode 600.
require_pattern '[ ! -L "$path" ]' "$helper"
require_pattern '[ -f "$path" ]' "$helper"
require_pattern 'owner mismatch' "$helper"
require_pattern 'mode must be 600' "$helper"

echo "authentication backup safety checks passed"
