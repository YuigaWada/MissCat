#!/usr/bin/env ruby

require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

repository_root = Pathname.new(File.expand_path("..", __dir__))
verifier = repository_root.join("scripts/verify-swift6-project-settings.rb")

def project(swift_version: "6.0", strict: "complete", suppress: false, flags: nil)
  suppress_setting = suppress ? "SWIFT_SUPPRESS_WARNINGS = YES;" : ""
  flags_setting = flags ? "OTHER_SWIFT_FLAGS = \"#{flags}\";" : ""
  configs = [
    ["C1", "Debug"], ["C2", "Release"],
    ["C3", "Debug"], ["C4", "Release"]
  ].map do |identifier, name|
    "#{identifier} = {isa = XCBuildConfiguration; buildSettings = {SWIFT_VERSION = #{swift_version}; SWIFT_STRICT_CONCURRENCY = #{strict}; #{suppress_setting} #{flags_setting}}; name = #{name}; };"
  end.join("\n")

  <<~PBX
    // !$*UTF8*$!
    { archiveVersion = 1; classes = {}; objectVersion = 56; objects = {
      T1 = {isa = PBXNativeTarget; buildConfigurationList = L1; name = FixtureApp;};
      T2 = {isa = PBXNativeTarget; buildConfigurationList = L2; name = FixtureTests;};
      L1 = {isa = XCConfigurationList; buildConfigurations = (C1, C2);};
      L2 = {isa = XCConfigurationList; buildConfigurations = (C3, C4);};
      #{configs}
      P1 = {isa = PBXProject; targets = (T1, T2);};
    }; rootObject = P1; }
  PBX
end

def verify(verifier, project_path)
  Open3.capture3(
    RbConfig.ruby,
    verifier.to_s,
    "--project", project_path.to_s,
    "--required-targets", "FixtureApp,FixtureTests"
  )
end

Dir.mktmpdir("misscat-swift6-settings-") do |directory|
  project_path = Pathname.new(directory).join("project.pbxproj")

  File.write(project_path, project)
  stdout, stderr, status = verify(verifier, project_path)
  abort "valid fixture failed: #{stdout}#{stderr}" unless status.success?

  File.write(project_path, project(swift_version: "5.0"))
  _, stderr, status = verify(verifier, project_path)
  abort "Swift 5 fixture unexpectedly passed" if status.success?
  abort "Swift version diagnostic absent" unless stderr.include?("SWIFT_VERSION must be 6.0")

  File.write(project_path, project(strict: "targeted"))
  _, stderr, status = verify(verifier, project_path)
  abort "targeted strictness fixture unexpectedly passed" if status.success?
  abort "strict concurrency diagnostic absent" unless stderr.include?("SWIFT_STRICT_CONCURRENCY must be complete")

  File.write(project_path, project(suppress: true))
  _, stderr, status = verify(verifier, project_path)
  abort "warning suppression fixture unexpectedly passed" if status.success?
  abort "warning suppression diagnostic absent" unless stderr.include?("must not suppress Swift warnings")

  File.write(project_path, project(flags: "-Xfrontend -strict-concurrency=minimal"))
  _, stderr, status = verify(verifier, project_path)
  abort "minimal concurrency flag fixture unexpectedly passed" if status.success?
  abort "flag suppression diagnostic absent" unless stderr.include?("suppression flag")
end

puts "Swift 6 project setting verifier fixtures passed."
