#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repository_root="$(cd "${script_dir}/.." && pwd -P)"
readonly verifier="${script_dir}/verify-swiftui-framework-ratio.rb"

fail() {
    printf 'SwiftUI framework ratio self-test failed: %s\n' "$*" >&2
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
    shift
    local gate_exit=0
    "$@" >"$output_path" 2>"${output_path}.stderr" || gate_exit=$?
    [[ "$gate_exit" -eq 1 ]] || fail "expected gate exit 1, received ${gate_exit}: $*"
}

[[ -x "$verifier" ]] || fail "verifier is not executable"

fixture_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/misscat-framework-ratio.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT

production_json="${fixture_dir}/production.json"
env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" >"$production_json"
assert_json "$production_json" '
  expected = {
    "total_swift" => 64,
    "uikit_only" => 2,
    "swiftui_only" => 25,
    "hybrid" => 3,
    "neutral" => 34,
    "rx_files" => 0,
    "polio_files" => 0,
    "legacy_loader_files" => 0,
    "legacy_loader_refs" => 0,
    "tracked_ib_artifacts" => 0
  }
  abort unless data.fetch("passed") && data.fetch("counts") == expected
  abort unless data.fetch("pure_swiftui_progress").values_at("numerator", "denominator", "basis_points") == [25, 30, 8333]
'

production_complete_json="${fixture_dir}/production-complete.json"
expect_gate_failure "$production_complete_json" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" --require-complete
assert_json "$production_complete_json" '
  abort if data.fetch("passed")
  abort unless data.fetch("mode") == "require-complete"
  required = %w[uikit_only hybrid]
  retired = %w[rx_files polio_files legacy_loader_files legacy_loader_refs tracked_ib_artifacts]
  abort unless required.all? { |key| data.fetch("violations").any? { |message| message.start_with?(key) } }
  abort if retired.any? { |key| data.fetch("violations").any? { |message| message.start_with?(key) } }
'

fixture_repository="${fixture_dir}/repository"
/bin/mkdir -p "${fixture_repository}/Fixture.xcodeproj" "${fixture_repository}/Sources"

printf '%s\n' \
    'import UIKit' \
    'let activeNib = UINib(nibName: "Fixture", bundle: nil)' \
    'let activeStoryboard = UIStoryboard(name: "Fixture", bundle: nil)' \
    '// let ignoredComment = UINib(nibName: "Ignored", bundle: nil)' \
    >"${fixture_repository}/Sources/UIKitOnly.swift"
printf '%s\n' 'import SwiftUI' >"${fixture_repository}/Sources/SwiftUIOnly.swift"
printf '%s\n' 'import UIKit' 'import SwiftUI' >"${fixture_repository}/Sources/Hybrid.swift"
printf '%s\n' 'import Foundation' >"${fixture_repository}/Sources/Neutral.swift"
printf '%s\n' 'import Foundation' 'import RxSwift' >"${fixture_repository}/Sources/Reactive.swift"
printf '%s\n' 'import PolioPager' >"${fixture_repository}/Sources/Pager.swift"
printf '%s\n' 'import UIKit' 'let ignored = UINib(nibName: "Ignored", bundle: nil)' \
    >"${fixture_repository}/Sources/IgnoredUIKit.swift"
printf '%s\n' '<document />' >"${fixture_repository}/Sources/Legacy.xib"

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
    printf '%s\n' '    B7 = {isa = PBXBuildFile; fileRef = F2; };'
    printf '%s\n' '    B8 = {isa = PBXBuildFile; fileRef = F4; };'
    printf '%s\n' '    F1 = {isa = PBXFileReference; path = UIKitOnly.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F2 = {isa = PBXFileReference; path = SwiftUIOnly.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F3 = {isa = PBXFileReference; path = Hybrid.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F4 = {isa = PBXFileReference; path = Neutral.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F5 = {isa = PBXFileReference; path = Reactive.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    F6 = {isa = PBXFileReference; path = Pager.swift; sourceTree = "<group>"; };'
    printf '%s\n' '    G1 = {isa = PBXGroup; children = (F1, F2, F3, F4, F5, F6); path = Sources; sourceTree = "<group>"; };'
    printf '%s\n' '    G0 = {isa = PBXGroup; children = (G1); sourceTree = "<group>"; };'
    printf '%s\n' '    S1 = {isa = PBXSourcesBuildPhase; files = (B1, B2, B3, B4, B5, B6); };'
    printf '%s\n' '    S2 = {isa = PBXSourcesBuildPhase; files = (B7, B8); };'
    printf '%s\n' '    T1 = {isa = PBXNativeTarget; buildPhases = (S1); name = FixtureApp; };'
    printf '%s\n' '    T2 = {isa = PBXNativeTarget; buildPhases = (S2); name = CompleteApp; };'
    printf '%s\n' '    P1 = {isa = PBXProject; mainGroup = G0; targets = (T1, T2); };'
    printf '%s\n' '  };'
    printf '%s\n' '  rootObject = P1;'
    printf '%s\n' '}'
} >"${fixture_repository}/Fixture.xcodeproj/project.pbxproj"

{
    printf '%s\n' '{'
    printf '%s\n' '  "schema_version": 1,'
    printf '%s\n' '  "target": "FixtureApp",'
    printf '%s\n' '  "counts": {'
    printf '%s\n' '    "total_swift": 6,'
    printf '%s\n' '    "uikit_only": 1,'
    printf '%s\n' '    "swiftui_only": 1,'
    printf '%s\n' '    "hybrid": 1,'
    printf '%s\n' '    "neutral": 3,'
    printf '%s\n' '    "rx_files": 1,'
    printf '%s\n' '    "polio_files": 1,'
    printf '%s\n' '    "legacy_loader_files": 1,'
    printf '%s\n' '    "legacy_loader_refs": 2,'
    printf '%s\n' '    "tracked_ib_artifacts": 1'
    printf '%s\n' '  }'
    printf '%s\n' '}'
} >"${fixture_repository}/fixture-baseline.json"

{
    printf '%s\n' '{'
    printf '%s\n' '  "schema_version": 1,'
    printf '%s\n' '  "target": "CompleteApp",'
    printf '%s\n' '  "counts": {'
    printf '%s\n' '    "total_swift": 2,'
    printf '%s\n' '    "uikit_only": 0,'
    printf '%s\n' '    "swiftui_only": 1,'
    printf '%s\n' '    "hybrid": 0,'
    printf '%s\n' '    "neutral": 1,'
    printf '%s\n' '    "rx_files": 0,'
    printf '%s\n' '    "polio_files": 0,'
    printf '%s\n' '    "legacy_loader_files": 0,'
    printf '%s\n' '    "legacy_loader_refs": 0,'
    printf '%s\n' '    "tracked_ib_artifacts": 0'
    printf '%s\n' '  }'
    printf '%s\n' '}'
} >"${fixture_repository}/complete-baseline.json"

/usr/bin/git -C "$fixture_repository" init -q
/usr/bin/git -C "$fixture_repository" config user.name YuigaWada
/usr/bin/git -C "$fixture_repository" config user.email yuigawada@gmail.com
/usr/bin/git -C "$fixture_repository" add .
/usr/bin/git -C "$fixture_repository" commit -qm 'fixture'

fixture_arguments=(
    --project "${fixture_repository}/Fixture.xcodeproj"
    --repository-root "$fixture_repository"
    --target FixtureApp
    --baseline "${fixture_repository}/fixture-baseline.json"
)

fixture_json="${fixture_dir}/fixture.json"
env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}" >"$fixture_json"
assert_json "$fixture_json" '
  expected = {
    "total_swift" => 6,
    "uikit_only" => 1,
    "swiftui_only" => 1,
    "hybrid" => 1,
    "neutral" => 3,
    "rx_files" => 1,
    "polio_files" => 1,
    "legacy_loader_files" => 1,
    "legacy_loader_refs" => 2,
    "tracked_ib_artifacts" => 1
  }
  abort unless data.fetch("passed") && data.fetch("counts") == expected
  abort unless data.fetch("pure_swiftui_progress").fetch("basis_points") == 3333
'

fixture_complete_json="${fixture_dir}/fixture-incomplete.json"
expect_gate_failure "$fixture_complete_json" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}" --require-complete
assert_json "$fixture_complete_json" 'abort if data.fetch("passed"); abort if data.fetch("violations").empty?'

/bin/cp "${fixture_repository}/Sources/UIKitOnly.swift" "${fixture_dir}/UIKitOnly.swift"
printf '%s\n' 'let regressionNib = UINib(nibName: "Regression", bundle: nil)' \
    >>"${fixture_repository}/Sources/UIKitOnly.swift"
loader_regression_json="${fixture_dir}/loader-regression.json"
expect_gate_failure "$loader_regression_json" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
assert_json "$loader_regression_json" '
  abort unless data.fetch("violations").include?("legacy_loader_refs increased from 2 to 3")
'
/bin/cp "${fixture_dir}/UIKitOnly.swift" "${fixture_repository}/Sources/UIKitOnly.swift"

/bin/cp "${fixture_repository}/Sources/SwiftUIOnly.swift" "${fixture_dir}/SwiftUIOnly.swift"
printf '%s\n' 'import Foundation' >"${fixture_repository}/Sources/SwiftUIOnly.swift"
progress_regression_json="${fixture_dir}/progress-regression.json"
expect_gate_failure "$progress_regression_json" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
assert_json "$progress_regression_json" '
  abort unless data.fetch("violations").any? { |message| message.start_with?("pure_swiftui_progress decreased") }
'
/bin/cp "${fixture_dir}/SwiftUIOnly.swift" "${fixture_repository}/Sources/SwiftUIOnly.swift"

printf '%s\n' '<document />' >"${fixture_repository}/Sources/Second.xib"
/usr/bin/git -C "$fixture_repository" add Sources/Second.xib
ib_regression_json="${fixture_dir}/ib-regression.json"
expect_gate_failure "$ib_regression_json" \
    env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" "${fixture_arguments[@]}"
assert_json "$ib_regression_json" '
  abort unless data.fetch("violations").include?("tracked_ib_artifacts increased from 1 to 2")
'
/usr/bin/git -C "$fixture_repository" rm -q -f Sources/Second.xib Sources/Legacy.xib

complete_json="${fixture_dir}/complete.json"
env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$verifier" \
    --project "${fixture_repository}/Fixture.xcodeproj" \
    --repository-root "$fixture_repository" \
    --target CompleteApp \
    --baseline "${fixture_repository}/complete-baseline.json" \
    --require-complete \
    >"$complete_json"
assert_json "$complete_json" '
  abort unless data.fetch("passed")
  abort unless data.fetch("counts") == {
    "total_swift" => 2,
    "uikit_only" => 0,
    "swiftui_only" => 1,
    "hybrid" => 0,
    "neutral" => 1,
    "rx_files" => 0,
    "polio_files" => 0,
    "legacy_loader_files" => 0,
    "legacy_loader_refs" => 0,
    "tracked_ib_artifacts" => 0
  }
  abort unless data.fetch("pure_swiftui_progress").fetch("basis_points") == 10_000
'

printf 'SwiftUI framework ratio verifier fixtures passed.\n'
