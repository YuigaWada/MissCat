#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repository_root="$(cd "${script_dir}/.." && pwd -P)"
readonly verifier="${script_dir}/verify-pod-linkage-boundary.rb"

fail() {
    printf 'Pod linkage boundary self-test failed: %s\n' "$*" >&2
    exit 1
}

expect_boundary_failure() {
    local label=$1
    local expected_message=$2
    local output_path=$3
    shift 3

    local gate_exit=0
    "$@" >"$output_path" 2>"${output_path}.stderr" || gate_exit=$?
    [[ "$gate_exit" -eq 1 ]] || fail "${label}: expected exit 1, received ${gate_exit}"
    rg -F -q -- "$expected_message" "${output_path}.stderr" || \
        fail "${label}: expected diagnostic was not emitted"
}

mutate_once() {
    local path=$1
    local before=$2
    local after=$3
    /usr/bin/ruby -e '
      path, before, after = ARGV
      source = File.binread(path)
      abort "fixture mutation did not match" unless source.sub!(before, after)
      File.binwrite(path, source)
    ' "$path" "$before" "$after"
}

[[ -x "$verifier" ]] || fail "verifier is not executable"

env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" >/dev/null

fixture_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/misscat-pod-linkage.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT

fixture_repository="${fixture_dir}/repository"
/bin/mkdir -p \
    "${fixture_repository}/MissCat.xcodeproj" \
    "${fixture_repository}/MissCat.xcworkspace"

reset_project() {
    /bin/cp \
        "${repository_root}/MissCat.xcodeproj/project.pbxproj" \
        "${fixture_repository}/MissCat.xcodeproj/project.pbxproj"
}

reset_podfile() {
    /bin/cp "${repository_root}/Podfile" "${fixture_repository}/Podfile"
}

reset_lock() {
    /bin/cp "${repository_root}/Podfile.lock" "${fixture_repository}/Podfile.lock"
}

reset_workspace() {
    /bin/cp \
        "${repository_root}/MissCat.xcworkspace/contents.xcworkspacedata" \
        "${fixture_repository}/MissCat.xcworkspace/contents.xcworkspacedata"
}

reset_project
reset_podfile
reset_lock
reset_workspace

fixture_arguments=(--repository-root "$fixture_repository")
env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    "$verifier" "${fixture_arguments[@]}" >/dev/null

project_path="${fixture_repository}/MissCat.xcodeproj/project.pbxproj"
failure_output="${fixture_dir}/failure.out"

mutate_once \
    "$project_path" \
    $'\t\t\t\t\t"\\"UIKit\\"",\n' \
    $'\t\t\t\t\t"\\"UIKit\\"",\n\t\t\t\t\t"-framework",\n\t\t\t\t\t"\\"RxSwift\\"",\n'
expect_boundary_failure \
    "retired framework" \
    "Debug OTHER_LDFLAGS" \
    "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"

reset_project
mutate_once \
    "$project_path" \
    $'\t\t\t\tFRAMEWORK_SEARCH_PATHS = (\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t);' \
    $'\t\t\t\tFRAMEWORK_SEARCH_PATHS = (\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"$(PROJECT_DIR)/Pods/_Prebuild/GeneratedFrameworks/Agrume",\n\t\t\t\t);'
expect_boundary_failure \
    "retired search path" \
    "Debug FRAMEWORK_SEARCH_PATHS" \
    "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"

reset_project
mutate_once \
    "$project_path" \
    $'\t\t\t\t\t"-framework",\n\t\t\t\t\t"\\"MisskeyKit\\"",\n' \
    ''
expect_boundary_failure \
    "missing current framework" \
    "Debug OTHER_LDFLAGS" \
    "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"

reset_project
mutate_once \
    "$project_path" \
    'path = "Target Support Files/Pods-MissCat/Pods-MissCat.debug.xcconfig";' \
    'path = "Target Support Files/Pods-MissCat/Retired.debug.xcconfig";'
expect_boundary_failure \
    "missing CocoaPods base configuration" \
    "Debug base configuration" \
    "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"

reset_project
mutate_once \
    "$project_path" \
    'path = Pods_MissCat.framework;' \
    'path = Retired.framework;'
expect_boundary_failure \
    "missing aggregate framework" \
    "app Frameworks phase" \
    "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"

reset_project
printf '%s\n' "pod 'RxSwift'" >>"${fixture_repository}/Podfile"
expect_boundary_failure \
    "retired direct dependency" \
    "Podfile direct dependencies" \
    "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
reset_podfile

mutate_once \
    "${fixture_repository}/Podfile.lock" \
    '  Starscream:' \
    '  RetiredStarscream:'
expect_boundary_failure \
    "changed locked graph" \
    "Podfile.lock root pods" \
    "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
reset_lock

mutate_once \
    "${fixture_repository}/MissCat.xcworkspace/contents.xcworkspacedata" \
    'location = "group:Pods/Pods.xcodeproj"' \
    'location = "group:Retired/Retired.xcodeproj"'
expect_boundary_failure \
    "missing Pods workspace reference" \
    "workspace must reference" \
    "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
reset_workspace

/bin/mkdir -p "${fixture_repository}/Pods"
/bin/cp "${fixture_repository}/Podfile.lock" "${fixture_repository}/Pods/Manifest.lock"
env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    "$verifier" "${fixture_arguments[@]}" >/dev/null
printf '\nmanifest drift\n' >>"${fixture_repository}/Pods/Manifest.lock"
expect_boundary_failure \
    "manifest drift" \
    "Pods/Manifest.lock differs" \
    "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"

printf 'Pod linkage boundary verifier fixtures passed.\n'
