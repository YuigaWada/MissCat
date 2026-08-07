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

# Every exit cleans the three simulator staging artifacts.
require_pattern 'trap cleanup EXIT' "$helper"
require_pattern 'rm -f -- "$sim_key" "$sim_input" "$sim_output"' "$helper"

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
