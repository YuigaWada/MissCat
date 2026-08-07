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
/bin/mkdir -p "${fixture_repository}/MissCat.xcodeproj" "${fixture_repository}/MissCat.xcworkspace"

reset_project() {
    /bin/cp "${repository_root}/MissCat.xcodeproj/project.pbxproj" "${fixture_repository}/MissCat.xcodeproj/project.pbxproj"
}

reset_workspace() {
    /bin/cp "${repository_root}/MissCat.xcworkspace/contents.xcworkspacedata" "${fixture_repository}/MissCat.xcworkspace/contents.xcworkspacedata"
}

reset_project
reset_workspace
fixture_arguments=(--repository-root "$fixture_repository")
env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}" >/dev/null

project_path="${fixture_repository}/MissCat.xcodeproj/project.pbxproj"
workspace_path="${fixture_repository}/MissCat.xcworkspace/contents.xcworkspacedata"
failure_output="${fixture_dir}/failure.out"
app_debug_prefix=$'\t\t8D4A2A32237437C100503685 /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n'

touch "${fixture_repository}/Podfile"
expect_boundary_failure "Podfile" "forbidden dependency artifact exists: Podfile" "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
rm "${fixture_repository}/Podfile"

/bin/mkdir "${fixture_repository}/Pods"
expect_boundary_failure "Pods sandbox" "forbidden dependency artifact exists: Pods" "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
/bin/rmdir "${fixture_repository}/Pods"

mutate_once "$project_path" "$app_debug_prefix" \
    $'\t\t8D4A2A32237437C100503685 /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbaseConfigurationReference = DEADBEEFDEADBEEFDEADBEEF;\n\t\t\tbuildSettings = {\n'
expect_boundary_failure "base configuration" "Debug base configuration must be absent" "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
reset_project

mutate_once "$project_path" "$app_debug_prefix" \
    $'\t\t8D4A2A32237437C100503685 /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n\t\t\t\tFRAMEWORK_SEARCH_PATHS = "$(inherited)";\n'
expect_boundary_failure "framework search path" "Debug FRAMEWORK_SEARCH_PATHS must be absent" "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
reset_project

mutate_once "$project_path" "$app_debug_prefix" \
    $'\t\t8D4A2A32237437C100503685 /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n\t\t\t\tOTHER_LDFLAGS = "$(inherited)";\n'
expect_boundary_failure "linker flags" "Debug OTHER_LDFLAGS must be absent" "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
reset_project

mutate_once "$workspace_path" '</Workspace>' \
    $'   <FileRef location = "group:Pods/Pods.xcodeproj"></FileRef>\n</Workspace>'
expect_boundary_failure "workspace" "workspace retains a CocoaPods reference" "$failure_output" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"

printf 'Pod linkage boundary verifier fixtures passed.\n'
