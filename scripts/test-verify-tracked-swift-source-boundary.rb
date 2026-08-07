#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

class FixtureFailure < StandardError; end

class BoundaryFixture
  def initialize(verifier)
    @verifier = verifier
    @root = Pathname.new(Dir.mktmpdir("misscat-source-boundary."))
    @project = @root.join("Fixture.xcodeproj/project.pbxproj")
    @manifest = @root.join("retired.json")
    @memberships = {
      "MissCat" => [
        "MissCat/Others/Platform/MissCatSystemClipboardWriter.swift",
        "MissCat/App.swift"
      ],
      "MissCatShare" => [
        "MissCatShare/ShareViewController.swift",
        "MissCatShare/ShareCore.swift"
      ],
      "MissCatTests" => ["MissCatTests/BoundaryTests.swift"]
    }
    @extra_file_references = []
  end

  def run
    create_repository
    assert_clean_fixture
    assert_unowned_source_is_rejected
    assert_membership_mutation_is_observed
    assert_dangling_pbx_references_are_rejected
    assert_retired_patterns_are_rejected
    assert_manifest_reappearance_is_rejected
    assert_rx_and_polio_are_rejected
    assert_unexpected_shipping_uikit_is_rejected
    assert_interface_builder_artifacts_are_rejected
  ensure
    FileUtils.remove_entry(@root) if @root&.directory?
  end

  private

  def create_repository
    write("MissCat/Others/Platform/MissCatSystemClipboardWriter.swift", "import UIKit\n")
    write("MissCat/App.swift", "import SwiftUI\n")
    write("MissCatShare/ShareViewController.swift", "import SwiftUI\nimport UIKit\n")
    write("MissCatShare/ShareCore.swift", "import Foundation\n")
    write("MissCatTests/BoundaryTests.swift", "import UIKit\nimport XCTest\n")
    write("Pods/Vendor.swift", "import UIKit\nimport RxSwift\n")
    write("ThirdParty/Library.swift", "import UIKit\n")
    write("Generated/Schema.swift", "import Foundation\n")
    write_project
    write_manifest

    git("init", "-q")
    git("config", "user.name", "YuigaWada")
    git("config", "user.email", "yuigawada@gmail.com")
    git("add", ".")
    git("commit", "-qm", "fixture")
  end

  def assert_clean_fixture
    status, data = verify
    assert(status == 0, "clean fixture failed: #{data.fetch("violations", [])}")
    assert(data.fetch("passed"), "clean fixture did not pass")
    assert(data.fetch("counts") == {
      "native_targets" => 3,
      "tracked_swift" => 8,
      "managed_swift" => 5,
      "excluded_swift" => 3,
      "owned_unique_swift" => 5,
      "unowned_swift" => 0,
      "tracked_ib_artifacts" => 0,
      "pbx_swift_file_references" => 5,
      "duplicate_pbx_swift_file_references" => 0,
      "dangling_pbx_swift_file_references" => 0,
      "unreferenced_managed_swift" => 0,
      "pbx_ib_file_references" => 0,
      "retired_reappearances" => 0,
      "retired_pattern_paths" => 0,
      "retired_pbx_reference_paths" => 0,
      "rx_or_polio_sources" => 0,
      "shipping_uikit_imports" => 2
    }, "clean fixture counts changed")
  end

  def assert_unowned_source_is_rejected
    track("Loose.swift", "import Foundation\n")
    status, data = verify
    assert(status == 1, "unowned source did not fail")
    assert(data.fetch("unowned_swift") == ["Loose.swift"], "wrong unowned source result")
    assert(data.fetch("unreferenced_managed_swift") == ["Loose.swift"], "missing PBX reference was not reported")
    untrack("Loose.swift")
  end

  def assert_membership_mutation_is_observed
    track("MissCatTests/AddedTests.swift", "import XCTest\n")
    status, = verify
    assert(status == 1, "unowned test source did not fail")

    @memberships.fetch("MissCatTests") << "MissCatTests/AddedTests.swift"
    write_project
    status, data = verify
    assert(status == 0, "PBX membership addition was not observed")
    assert(data.dig("targets", "MissCatTests", "count") == 2, "target count did not update")

    @memberships.fetch("MissCatTests").delete("MissCatTests/AddedTests.swift")
    write_project
    untrack("MissCatTests/AddedTests.swift")
  end

  def assert_dangling_pbx_references_are_rejected
    @extra_file_references << "Retired/Removed.swift"
    write_project
    status, data = verify
    assert(status == 1, "dangling PBX Swift reference did not fail")
    assert(
      data.fetch("dangling_pbx_swift_file_references") == ["Retired/Removed.swift"],
      "dangling PBX Swift reference was not reported"
    )
    assert(
      data.fetch("retired_pbx_reference_paths") == ["Retired/Removed.swift"],
      "manifest-listed PBX reference was not reported"
    )
    @extra_file_references.delete("Retired/Removed.swift")

    @extra_file_references << "MissCat/Legacy.storyboard"
    write_project
    status, data = verify
    assert(status == 1, "dangling PBX storyboard reference did not fail")
    assert(
      data.fetch("pbx_ib_file_references") == ["MissCat/Legacy.storyboard"],
      "PBX storyboard reference was not reported"
    )
    @extra_file_references.delete("MissCat/Legacy.storyboard")
    write_project
  end

  def assert_retired_patterns_are_rejected
    {
      "MissCat/View/NewView.swift" => "import SwiftUI\n",
      "Modern/LegacyViewController.swift" => "import SwiftUI\n",
      "Modern/LegacyViewModel.swift" => "import Foundation\n",
      "MissCat/Others/App/SceneDelegate.swift" => "import SwiftUI\n"
    }.each do |path, contents|
      track(path, contents)
      status, data = verify
      assert(status == 1, "retired pattern did not fail: #{path}")
      assert(data.fetch("retired_pattern_paths").include?(path), "retired pattern was not reported: #{path}")
      untrack(path)
    end
  end

  def assert_manifest_reappearance_is_rejected
    track("Retired/Removed.swift", "import Foundation\n")
    status, data = verify
    assert(status == 1, "manifest source reappearance did not fail")
    assert(data.fetch("retired_reappearances") == ["Retired/Removed.swift"], "manifest source was not reported")
    untrack("Retired/Removed.swift")
  end

  def assert_rx_and_polio_are_rejected
    track("LegacyDependencies.swift", "import RxSwift\nimport PolioPager\n")
    status, data = verify
    assert(status == 1, "Rx/Polio source did not fail")
    assert(data.fetch("rx_or_polio_sources") == [{
      "path" => "LegacyDependencies.swift",
      "imports" => ["PolioPager", "RxSwift"]
    }], "Rx/Polio imports were not reported")
    untrack("LegacyDependencies.swift")
  end

  def assert_unexpected_shipping_uikit_is_rejected
    track("MissCat/UnexpectedUIKit.swift", "import UIKit\n")
    @memberships.fetch("MissCat") << "MissCat/UnexpectedUIKit.swift"
    write_project
    status, data = verify
    assert(status == 1, "unexpected shipping UIKit source did not fail")
    assert(
      data.fetch("violations").include?(
        "UIKit import is outside the active shipping OS-boundary allowlist: MissCat/UnexpectedUIKit.swift"
      ),
      "unexpected UIKit source was not reported"
    )
    @memberships.fetch("MissCat").delete("MissCat/UnexpectedUIKit.swift")
    write_project
    untrack("MissCat/UnexpectedUIKit.swift")
  end

  def assert_interface_builder_artifacts_are_rejected
    track("MissCat/Legacy.xib", "<document />\n")
    status, data = verify
    assert(status == 1, "tracked XIB did not fail")
    assert(data.fetch("tracked_ib_artifacts") == ["MissCat/Legacy.xib"], "tracked XIB was not reported")
    assert(data.dig("counts", "tracked_ib_artifacts") == 1, "tracked XIB count was not exact")
    untrack("MissCat/Legacy.xib")
  end

  def write_project
    paths = (@memberships.values.flatten + @extra_file_references).uniq.sort
    file_ids = paths.each_with_index.to_h { |path, index| [path, "F#{index + 1}"] }
    build_index = 0
    build_files = []
    phases = []
    targets = []

    @memberships.sort.each_with_index do |(target, target_paths), target_index|
      build_ids = target_paths.map do |path|
        build_index += 1
        build_id = "B#{build_index}"
        build_files << "    #{build_id} = {isa = PBXBuildFile; fileRef = #{file_ids.fetch(path)}; };"
        build_id
      end
      phase_id = "S#{target_index + 1}"
      target_id = "T#{target_index + 1}"
      phases << "    #{phase_id} = {isa = PBXSourcesBuildPhase; files = (#{build_ids.join(", ")}); };"
      targets << "    #{target_id} = {isa = PBXNativeTarget; buildPhases = (#{phase_id}); name = #{target}; };"
    end

    references = paths.map do |path|
      "    #{file_ids.fetch(path)} = {isa = PBXFileReference; path = \"#{path}\"; sourceTree = SOURCE_ROOT; };"
    end
    target_ids = (1..@memberships.length).map { |index| "T#{index}" }
    objects = build_files + references + phases + targets + [
      "    G1 = {isa = PBXGroup; children = (); sourceTree = \"<group>\"; };",
      "    P1 = {isa = PBXProject; mainGroup = G1; targets = (#{target_ids.join(", ")}); };"
    ]
    write(
      "Fixture.xcodeproj/project.pbxproj",
      [
        "// !$*UTF8*$!",
        "{",
        "  archiveVersion = 1;",
        "  classes = {};",
        "  objectVersion = 51;",
        "  objects = {",
        objects.join("\n"),
        "  };",
        "  rootObject = P1;",
        "}",
        ""
      ].join("\n")
    )
  end

  def write_manifest
    write(
      "retired.json",
      JSON.pretty_generate(
        "schema_version" => 1,
        "retired_unowned_count" => 1,
        "files" => [{ "path" => "Retired/Removed.swift" }]
      ) + "\n"
    )
  end

  def verify
    stdout, stderr, status = Open3.capture3(
      @verifier.to_s,
      "--project", @project.to_s,
      "--repository-root", @root.to_s,
      "--manifest", @manifest.to_s
    )
    unless [0, 1].include?(status.exitstatus)
      raise FixtureFailure, "verifier exited #{status.exitstatus}: #{stderr}"
    end
    [status.exitstatus, JSON.parse(stdout)]
  rescue JSON::ParserError => error
    raise FixtureFailure, "verifier emitted invalid JSON: #{error.message}; stderr=#{stderr.inspect}"
  end

  def track(path, contents)
    write(path, contents)
    git("add", path)
  end

  def untrack(path)
    git("rm", "-q", "-f", "--", path)
  end

  def write(path, contents)
    destination = @root.join(path)
    FileUtils.mkdir_p(destination.dirname)
    File.write(destination, contents, encoding: "UTF-8")
  end

  def git(*arguments)
    stdout, stderr, status = Open3.capture3("/usr/bin/git", "-C", @root.to_s, *arguments)
    return stdout if status.success?

    raise FixtureFailure, "git #{arguments.join(" ")} failed: #{stderr}"
  end

  def assert(condition, message)
    raise FixtureFailure, message unless condition
  end
end

verifier = Pathname.new(__dir__).join("verify-tracked-swift-source-boundary.rb").realpath
BoundaryFixture.new(verifier).run
puts "tracked Swift source boundary verifier fixtures passed."
