#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly verifier="${script_dir}/verify-swiftui-framework-aggregate.rb"

fail() {
    printf 'Aggregate SwiftUI framework self-test failed: %s\n' "$*" >&2
    exit 1
}

assert_json() {
    local json_path=$1
    local ruby_assertion=$2
    /usr/bin/ruby -rjson -e "data = JSON.parse(File.read(ARGV.fetch(0))); ${ruby_assertion}" "$json_path" || \
        fail "JSON assertion failed for ${json_path}"
}

expect_gate_failure() {
    local output_path=$1
    local expected_status=$2
    shift 2
    local gate_status=0
    "$@" >"$output_path" 2>"${output_path}.stderr" || gate_status=$?
    [[ "$gate_status" -eq "$expected_status" ]] || \
        fail "expected gate exit ${expected_status}, received ${gate_status}: $*"
}

[[ -x "$verifier" ]] || fail "aggregate verifier is not executable"

fixture_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/misscat-framework-aggregate.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT
fixture_repository="${fixture_dir}/repository"
/bin/mkdir -p "${fixture_repository}/Fixture.xcodeproj" "${fixture_repository}/Sources"

printf '%s\n' 'import UIKit' >"${fixture_repository}/Sources/AppUIKit.swift"
printf '%s\n' 'import SwiftUI' >"${fixture_repository}/Sources/AppSwiftUI.swift"
printf '%s\n' 'import Foundation' >"${fixture_repository}/Sources/AppNeutral.swift"
printf '%s\n' 'import SwiftUI' >"${fixture_repository}/Sources/ShareSwiftUI.swift"
printf '%s\n' 'import UIKit' 'import SwiftUI' >"${fixture_repository}/Sources/SharePrincipal.swift"
printf '%s\n' 'import Foundation' >"${fixture_repository}/Sources/ShareNeutral.swift"
printf '%s\n' 'import UIKit' 'let ignored = UINib(nibName: "Ignored", bundle: nil)' \
    >"${fixture_repository}/Sources/OffTargetUIKit.swift"

{
    printf '%s\n' '// !$*UTF8*$!'
    printf '%s\n' '{'
    printf '%s\n' '  archiveVersion = 1;'
    printf '%s\n' '  classes = {};'
    printf '%s\n' '  objectVersion = 51;'
    printf '%s\n' '  objects = {'
    printf '%s\n' '    B1 = {isa = PBXBuildFile; fileRef = F1; };'
    printf '%s\n' '    B2 = {isa = PBXBuildFile; fileRef = F2; };'
    printf '%s\n' '    B3 = {isa = PBXBuildFile; fileRef = F3; };'
    printf '%s\n' '    B4 = {isa = PBXBuildFile; fileRef = F4; };'
    printf '%s\n' '    B5 = {isa = PBXBuildFile; fileRef = F5; };'
    printf '%s\n' '    B6 = {isa = PBXBuildFile; fileRef = F6; };'
    printf '%s\n' '    B7 = {isa = PBXBuildFile; fileRef = F7; };'
    printf '%s\n' '    F1 = {isa = PBXFileReference; path = AppUIKit.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F2 = {isa = PBXFileReference; path = AppSwiftUI.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F3 = {isa = PBXFileReference; path = AppNeutral.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F4 = {isa = PBXFileReference; path = ShareSwiftUI.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F5 = {isa = PBXFileReference; path = SharePrincipal.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F6 = {isa = PBXFileReference; path = ShareNeutral.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F7 = {isa = PBXFileReference; path = OffTargetUIKit.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    G1 = {isa = PBXGroup; children = (F1, F2, F3, F4, F5, F6, F7); path = Sources; sourceTree = "<group>"; };'
    printf '%s\n' '    G0 = {isa = PBXGroup; children = (G1); sourceTree = "<group>"; };'
    printf '%s\n' '    S1 = {isa = PBXSourcesBuildPhase; files = (B1, B2, B3); };'
    printf '%s\n' '    S2 = {isa = PBXSourcesBuildPhase; files = (B4, B5, B6); };'
    printf '%s\n' '    T1 = {isa = PBXNativeTarget; buildPhases = (S1); name = MissCat; };'
    printf '%s\n' '    T2 = {isa = PBXNativeTarget; buildPhases = (S2); name = MissCatShare; };'
    printf '%s\n' '    P1 = {isa = PBXProject; mainGroup = G0; targets = (T1, T2); };'
    printf '%s\n' '  };'
    printf '%s\n' '  rootObject = P1;'
    printf '%s\n' '}'
} >"${fixture_repository}/Fixture.xcodeproj/project.pbxproj"

{
    printf '%s\n' '{'
    printf '%s\n' '  "schema_version": 1,'
    printf '%s\n' '  "targets": {'
    printf '%s\n' '    "MissCat": {"counts": {"total_swift": 3, "uikit_only": 1, "swiftui_only": 1, "hybrid": 0, "neutral": 1, "rx_files": 0, "polio_files": 0, "legacy_loader_files": 0, "legacy_loader_refs": 0, "tracked_ib_artifacts": 0}},'
    printf '%s\n' '    "MissCatShare": {"counts": {"total_swift": 3, "uikit_only": 0, "swiftui_only": 1, "hybrid": 1, "neutral": 1, "rx_files": 0, "polio_files": 0, "legacy_loader_files": 0, "legacy_loader_refs": 0, "tracked_ib_artifacts": 0}}'
    printf '%s\n' '  },'
    printf '%s\n' '  "aggregate": {"counts": {"total_swift": 6, "uikit_only": 1, "swiftui_only": 2, "hybrid": 1, "neutral": 2, "rx_files": 0, "polio_files": 0, "legacy_loader_files": 0, "legacy_loader_refs": 0, "tracked_ib_artifacts": 0}}'
    printf '%s\n' '}'
} >"${fixture_repository}/aggregate-baseline.json"

/usr/bin/git -C "$fixture_repository" init -q
/usr/bin/git -C "$fixture_repository" config user.name YuigaWada
/usr/bin/git -C "$fixture_repository" config user.email yuigawada@gmail.com
/usr/bin/git -C "$fixture_repository" add .
/usr/bin/git -C "$fixture_repository" commit -qm 'fixture'

fixture_arguments=(
    --project "${fixture_repository}/Fixture.xcodeproj"
    --repository-root "$fixture_repository"
    --baseline "${fixture_repository}/aggregate-baseline.json"
)

fixture_json="${fixture_dir}/fixture.json"
env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}" >"$fixture_json"
assert_json "$fixture_json" '
  abort unless data.fetch("passed")
  abort unless data.dig("targets", "MissCat", "counts").values_at("total_swift", "uikit_only", "swiftui_only", "hybrid", "neutral") == [3, 1, 1, 0, 1]
  abort unless data.dig("targets", "MissCatShare", "counts").values_at("total_swift", "uikit_only", "swiftui_only", "hybrid", "neutral") == [3, 0, 1, 1, 1]
  abort unless data.dig("aggregate", "counts") == {"total_swift" => 6, "uikit_only" => 1, "swiftui_only" => 2, "hybrid" => 1, "neutral" => 2, "rx_files" => 0, "polio_files" => 0, "legacy_loader_files" => 0, "legacy_loader_refs" => 0, "tracked_ib_artifacts" => 0}
  abort unless data.dig("aggregate", "pure_swiftui_progress").values_at("numerator", "denominator", "fraction", "basis_points", "percent") == [2, 4, "2/4", 5000, 50.0]
'

complete_failure_json="${fixture_dir}/require-complete.json"
expect_gate_failure "$complete_failure_json" 1 \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}" --require-complete
assert_json "$complete_failure_json" '
  blockers = data.fetch("completion_blockers")
  abort unless blockers.map { |entry| entry.fetch("scope") } == ["MissCat", "MissCatShare"]
  abort unless blockers[0].fetch("reason").include?("App shipping target")
  abort unless blockers[1].fetch("reason").include?("NSExtensionPrincipalClass")
'

/bin/cp "${fixture_repository}/Fixture.xcodeproj/project.pbxproj" "${fixture_dir}/project.pbxproj"
/usr/bin/ruby -pi -e 'sub("files = (B4, B5, B6);", "files = (B4, B5, B6, B7);")' \
    "${fixture_repository}/Fixture.xcodeproj/project.pbxproj"
membership_json="${fixture_dir}/membership-regression.json"
expect_gate_failure "$membership_json" 1 \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
assert_json "$membership_json" '
  abort unless data.dig("targets", "MissCatShare", "counts", "uikit_only") == 1
  abort unless data.fetch("violations").include?("targets.MissCatShare.uikit_only increased from 0 to 1")
  abort unless data.fetch("violations").include?("aggregate.uikit_only increased from 1 to 2")
'
/bin/cp "${fixture_dir}/project.pbxproj" "${fixture_repository}/Fixture.xcodeproj/project.pbxproj"

/bin/cp "${fixture_repository}/Sources/AppNeutral.swift" "${fixture_dir}/AppNeutral.swift"
printf '%s\n' 'import Foundation' 'import RxSwift' 'import PolioPager' \
    >"${fixture_repository}/Sources/AppNeutral.swift"
dependency_json="${fixture_dir}/dependency-regression.json"
expect_gate_failure "$dependency_json" 1 \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
assert_json "$dependency_json" '
  abort unless data.dig("targets", "MissCat", "counts").values_at("rx_files", "polio_files") == [1, 1]
  abort unless data.dig("aggregate", "counts").values_at("rx_files", "polio_files") == [1, 1]
'
/bin/cp "${fixture_dir}/AppNeutral.swift" "${fixture_repository}/Sources/AppNeutral.swift"

/bin/cp "${fixture_repository}/Sources/AppUIKit.swift" "${fixture_dir}/AppUIKit.swift"
printf '%s\n' 'let activeLoader = UINib(nibName: "Fixture", bundle: nil)' \
    >>"${fixture_repository}/Sources/AppUIKit.swift"
loader_json="${fixture_dir}/loader-regression.json"
expect_gate_failure "$loader_json" 1 \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
assert_json "$loader_json" '
  abort unless data.dig("targets", "MissCat", "counts").values_at("legacy_loader_files", "legacy_loader_refs") == [1, 1]
  abort unless data.dig("aggregate", "counts").values_at("legacy_loader_files", "legacy_loader_refs") == [1, 1]
'
/bin/cp "${fixture_dir}/AppUIKit.swift" "${fixture_repository}/Sources/AppUIKit.swift"

printf '%s\n' '<document />' >"${fixture_repository}/Sources/Regression.xib"
/usr/bin/git -C "$fixture_repository" add Sources/Regression.xib
ib_json="${fixture_dir}/ib-regression.json"
expect_gate_failure "$ib_json" 1 \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
assert_json "$ib_json" '
  abort unless data.dig("targets", "MissCat", "counts", "tracked_ib_artifacts") == 1
  abort unless data.dig("targets", "MissCatShare", "counts", "tracked_ib_artifacts") == 1
  abort unless data.dig("aggregate", "counts", "tracked_ib_artifacts") == 1
  abort unless data.fetch("violations").include?("aggregate.tracked_ib_artifacts increased from 0 to 1")
'
/usr/bin/git -C "$fixture_repository" rm -q -f Sources/Regression.xib

/bin/cp "${fixture_repository}/Sources/AppSwiftUI.swift" "${fixture_dir}/AppSwiftUI.swift"
printf '%s\n' 'import Foundation' >"${fixture_repository}/Sources/AppSwiftUI.swift"
progress_json="${fixture_dir}/progress-regression.json"
expect_gate_failure "$progress_json" 1 \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
assert_json "$progress_json" '
  abort unless data.fetch("violations").any? { |message| message.start_with?("targets.MissCat.pure_swiftui_progress decreased") }
  abort unless data.fetch("violations").any? { |message| message.start_with?("aggregate.pure_swiftui_progress decreased") }
'
/bin/cp "${fixture_dir}/AppSwiftUI.swift" "${fixture_repository}/Sources/AppSwiftUI.swift"

/bin/cp "${fixture_repository}/aggregate-baseline.json" "${fixture_dir}/aggregate-baseline.json"
/usr/bin/ruby -rjson -e '
  path = ARGV.fetch(0)
  data = JSON.parse(File.read(path))
  counts = data.fetch("aggregate").fetch("counts")
  counts["total_swift"] += 1
  counts["neutral"] += 1
  File.write(path, JSON.pretty_generate(data))
' "${fixture_repository}/aggregate-baseline.json"
invalid_baseline_json="${fixture_dir}/invalid-baseline.json"
expect_gate_failure "$invalid_baseline_json" 2 \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
/usr/bin/grep -q 'aggregate baseline counts do not equal the sum of target memberships' \
    "${invalid_baseline_json}.stderr" || fail "invalid aggregate baseline was not rejected"
/bin/cp "${fixture_dir}/aggregate-baseline.json" "${fixture_repository}/aggregate-baseline.json"

printf '%s\n' 'import SwiftUI' >"${fixture_repository}/Sources/AppUIKit.swift"
printf '%s\n' 'import SwiftUI' >"${fixture_repository}/Sources/SharePrincipal.swift"
complete_json="${fixture_dir}/complete.json"
env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}" --require-complete \
    >"$complete_json"
assert_json "$complete_json" '
  abort unless data.fetch("passed") && data.fetch("completion_blockers").empty?
  abort unless data.dig("aggregate", "counts").values_at("uikit_only", "swiftui_only", "hybrid", "neutral") == [0, 4, 0, 2]
  abort unless data.dig("aggregate", "pure_swiftui_progress").fetch("basis_points") == 10_000
'

printf 'Aggregate SwiftUI framework verifier fixtures passed.\n'
