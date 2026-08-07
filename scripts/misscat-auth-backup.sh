#!/bin/bash
set -euo pipefail

usage() {
  echo "usage: $0 export|clear|restore <simulator-udid>" >&2
  exit 64
}

[ "$#" -eq 2 ] || usage
operation="$1"
device="$2"
case "$operation" in
  export|clear|restore) ;;
  *) usage ;;
esac
case "$device" in
  ????????-????-????-????-????????????) ;;
  *) echo "invalid simulator UDID" >&2; exit 64 ;;
esac

bundle_id="yuwd.MissCat"
app_group="group.yuwd.MissCat"
key_path="${HOME}/.config/misscat/auth-backup.key"
backup_path="${HOME}/Desktop/MissCatAuthBackup.enc"
key_tmp=""
backup_tmp=""
current_uid="$(id -u)"

group_listing="$(xcrun simctl get_app_container "$device" "$bundle_id" groups)"
group_path="$(printf '%s\n' "$group_listing" | awk -v group="$app_group" '$1 == group { print $2 }')"
case "$group_path" in
  */CoreSimulator/Devices/"$device"/data/Containers/Shared/AppGroup/*) ;;
  *) echo "shared app-group container not found" >&2; exit 1 ;;
esac

prefs_path="$group_path/Library/Preferences/$app_group.plist"
sim_key="$group_path/.misscat-auth-backup-key"
sim_input="$group_path/.misscat-auth-backup-input.enc"
sim_output="$group_path/.misscat-auth-backup-output.enc"

remove_staging_artifacts() {
  cleanup_status=0
  rm -f -- "$sim_key" || cleanup_status=1
  rm -f -- "$sim_input" || cleanup_status=1
  rm -f -- "$sim_output" || cleanup_status=1
  return "$cleanup_status"
}

assert_staging_absent() {
  for staged_path in "$sim_key" "$sim_input" "$sim_output"; do
    if [ -e "$staged_path" ] || [ -L "$staged_path" ]; then
      echo "simulator authentication staging cleanup incomplete" >&2
      return 1
    fi
  done
}

remove_host_temporaries() {
  cleanup_status=0
  if [ -n "$key_tmp" ]; then rm -f -- "$key_tmp" || cleanup_status=1; fi
  if [ -n "$backup_tmp" ]; then rm -f -- "$backup_tmp" || cleanup_status=1; fi
  return "$cleanup_status"
}

cleanup_on_exit() {
  exit_status="$?"
  trap - EXIT
  remove_staging_artifacts || exit_status=1
  assert_staging_absent || exit_status=1
  remove_host_temporaries || exit_status=1
  exit "$exit_status"
}

finalize_operation() {
  completed_operation="$1"
  if ! remove_staging_artifacts; then
    echo "$completed_operation staging cleanup failed" >&2
    return 1
  fi
  assert_staging_absent || return 1
  echo "$completed_operation succeeded"
}

trap cleanup_on_exit EXIT
trap 'exit 1' HUP INT TERM
if ! remove_staging_artifacts; then
  echo "initial simulator staging cleanup failed" >&2
  exit 1
fi
assert_staging_absent

validate_secure_file() {
  path="$1"
  label="$2"
  require_nonempty="$3"
  [ -e "$path" ] || { echo "$label not found" >&2; exit 1; }
  [ ! -L "$path" ] || { echo "$label must not be a symlink" >&2; exit 1; }
  [ -f "$path" ] || { echo "$label must be a regular file" >&2; exit 1; }
  [ "$(stat -f '%u' "$path")" = "$current_uid" ] || { echo "$label owner mismatch" >&2; exit 1; }
  [ "$(stat -f '%Lp' "$path")" = "600" ] || { echo "$label mode must be 600" >&2; exit 1; }
  if [ "$require_nonempty" = "true" ]; then
    [ -s "$path" ] || { echo "$label must not be empty" >&2; exit 1; }
  fi
}

validate_key() {
  validate_secure_file "$key_path" "backup key" true
  [ "$(stat -f '%z' "$key_path")" = "32" ] || { echo "backup key size is invalid" >&2; exit 1; }
}

validate_backup() {
  validate_secure_file "$backup_path" "encrypted backup" true
}

install_key() {
  validate_key
  install -m 600 "$key_path" "$sim_key"
}

stage_backup() {
  validate_backup
  install -m 600 "$backup_path" "$sim_input"
}

wait_for_result() {
  expected="$1"
  expected_nonce="$2"
  for _ in $(seq 1 30); do
    if [ -f "$prefs_path" ]; then
      result_operation="$(plutil -extract auth-backup-result.operation raw -o - "$prefs_path" 2>/dev/null || true)"
      result_nonce="$(plutil -extract auth-backup-result.nonce raw -o - "$prefs_path" 2>/dev/null || true)"
      result_success="$(plutil -extract auth-backup-result.success raw -o - "$prefs_path" 2>/dev/null || true)"
      if [ "$result_operation" = "$expected" ] && [ "$result_nonce" = "$expected_nonce" ]; then
        [ "$result_success" = "true" ] || { echo "$expected failed" >&2; exit 1; }
        return
      fi
    fi
    sleep 1
  done
  echo "$expected timed out" >&2
  exit 1
}

launch_operation() {
  requested_operation="$1"
  nonce="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  xcrun simctl terminate "$device" "$bundle_id" >/dev/null 2>&1 || true
  case "$requested_operation" in
    export)
      xcrun simctl launch "$device" "$bundle_id" \
        --auth-backup-export --auth-backup-nonce "$nonce" >/dev/null
      ;;
    preflight)
      xcrun simctl launch "$device" "$bundle_id" \
        --auth-backup-preflight --auth-backup-nonce "$nonce" >/dev/null
      ;;
    clear)
      xcrun simctl launch "$device" "$bundle_id" \
        --auth-backup-clear --auth-backup-nonce "$nonce" >/dev/null
      ;;
    restore)
      xcrun simctl launch "$device" "$bundle_id" \
        --auth-backup-restore --auth-backup-nonce "$nonce" --auth-api-probe >/dev/null
      ;;
  esac
  wait_for_result "$requested_operation" "$nonce"
}

case "$operation" in
  export)
    umask 077
    key_directory="$(dirname "$key_path")"
    backup_directory="$(dirname "$backup_path")"
    mkdir -p "$key_directory" "$backup_directory"
    [ ! -L "$key_directory" ] || { echo "backup key directory must not be a symlink" >&2; exit 1; }
    [ ! -L "$backup_directory" ] || { echo "backup directory must not be a symlink" >&2; exit 1; }
    if [ -e "$key_path" ]; then
      validate_key
    else
      key_tmp="$(mktemp "$key_directory/.auth-backup.key.XXXXXX")"
      openssl rand 32 > "$key_tmp"
      chmod 600 "$key_tmp"
      mv -f "$key_tmp" "$key_path"
      key_tmp=""
      validate_key
    fi
    if [ -e "$backup_path" ]; then validate_backup; fi
    install_key
    launch_operation export
    validate_secure_file "$sim_output" "simulator encrypted output" true
    backup_tmp="$(mktemp "$backup_directory/.MissCatAuthBackup.enc.XXXXXX")"
    install -m 600 "$sim_output" "$backup_tmp"
    mv -f "$backup_tmp" "$backup_path"
    backup_tmp=""
    validate_backup
    finalize_operation export
    echo "backup_sha256=$(openssl dgst -sha256 "$backup_path" | awk '{print $NF}')"
    echo "backup_mode=$(stat -f '%Lp' "$backup_path") key_mode=$(stat -f '%Lp' "$key_path")"
    ;;
  clear)
    # A destructive clear is authorized only by a fresh, app-verified receipt
    # for this exact account and decryptable host backup.
    install_key
    stage_backup
    launch_operation preflight
    if ! remove_staging_artifacts; then
      echo "preflight staging cleanup failed" >&2
      exit 1
    fi
    assert_staging_absent
    launch_operation clear
    finalize_operation clear
    ;;
  restore)
    install_key
    stage_backup
    launch_operation restore
    finalize_operation restore
    ;;
esac
