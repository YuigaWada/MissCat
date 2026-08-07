#!/usr/bin/env ruby

require "json"
require "open3"
require "optparse"
require "pathname"

EXPECTED_DIRECT_DEPENDENCIES = %w[
  Firebase/Messaging
  MisskeyKit
].freeze

EXPECTED_ROOT_PODS = %w[
  Firebase
  FirebaseCore
  FirebaseCoreDiagnostics
  FirebaseInstallations
  FirebaseMessaging
  GoogleDataTransport
  GoogleUtilities
  MisskeyKit
  PromisesObjC
  Starscream
  nanopb
].freeze

EXPECTED_CONFIGURATIONS = %w[Debug Release].freeze
EXPECTED_APP_FRAMEWORKS = %w[Foundation MisskeyKit Starscream UIKit].freeze
EXPECTED_SEARCH_PATHS = ["$(inherited)"].freeze
EXPECTED_POD_PHASES = [
  "[CP] Check Pods Manifest.lock",
  "[CP] Embed Pods Frameworks"
].freeze

class BoundaryError < StandardError; end

def read_file(path)
  File.read(path, encoding: "UTF-8")
rescue Errno::ENOENT
  raise BoundaryError, "required file is missing: #{path}"
end

def parse_top_level_block(text, heading)
  lines = text.lines
  start_index = lines.index { |line| line.chomp == "#{heading}:" }
  raise BoundaryError, "Podfile.lock has no #{heading} block" unless start_index

  block = []
  lines[(start_index + 1)..-1].each do |line|
    break if line.match?(/\A\S/)

    block << line
  end
  block
end

def podfile_dependencies(text)
  declaration_pattern = Regexp.new("^\\s*pod\\s+['\"]([^'\"]+)['\"]")
  text.each_line.each_with_object([]) do |line, dependencies|
    match = line.match(declaration_pattern)
    dependencies << match[1] if match
  end
end

def lock_dependencies(text)
  parse_top_level_block(text, "DEPENDENCIES").each_with_object([]) do |line, dependencies|
    next unless line =~ /^  - (.+)$/

    dependencies << Regexp.last_match(1).sub(/ \(.+\)$/, "")
  end
end

def lock_root_pods(text)
  parse_top_level_block(text, "SPEC CHECKSUMS").each_with_object([]) do |line, pods|
    match = line.match(/^  ([^:]+):\s*[0-9a-f]+\s*$/)
    pods << match[1] if match
  end
end

def project_objects(project_path)
  stdout, stderr, status = Open3.capture3(
    "/usr/bin/plutil",
    "-convert",
    "json",
    "-o",
    "-",
    project_path.to_s
  )
  unless status.success?
    detail = stderr.strip.empty? ? "plutil exited #{status.exitstatus}" : stderr.strip
    raise BoundaryError, "PBX project could not be parsed: #{detail}"
  end

  JSON.parse(stdout).fetch("objects")
rescue JSON::ParserError, KeyError => error
  raise BoundaryError, "PBX project JSON is invalid: #{error.message}"
end

def expected_ldflags
  ["$(inherited)"] + EXPECTED_APP_FRAMEWORKS.flat_map do |framework|
    ["-framework", %Q{"#{framework}"}]
  end
end

options = {}
parser = OptionParser.new do |arguments|
  arguments.banner = "usage: scripts/verify-pod-linkage-boundary.rb [options]"
  arguments.on("--repository-root PATH", "repository root") do |value|
    options[:repository_root] = value
  end
  arguments.on("--project PATH", "project.pbxproj path") do |value|
    options[:project] = value
  end
  arguments.on("--target NAME", "app target (default: MissCat)") do |value|
    options[:target] = value
  end
  arguments.on("-h", "--help", "show this help") do
    puts arguments
    exit 0
  end
end

begin
  parser.parse!
  raise OptionParser::InvalidOption, ARGV.join(" ") unless ARGV.empty?

  repository_root = Pathname.new(
    File.expand_path(options[:repository_root] || File.expand_path("..", __dir__))
  )
  project_path = Pathname.new(
    File.expand_path(
      options[:project] || repository_root.join("MissCat.xcodeproj/project.pbxproj")
    )
  )
  target_name = options[:target] || "MissCat"

  violations = []
  podfile = read_file(repository_root.join("Podfile"))
  lock = read_file(repository_root.join("Podfile.lock"))

  direct_in_podfile = podfile_dependencies(podfile).sort
  direct_in_lock = lock_dependencies(lock).sort
  expected_direct = EXPECTED_DIRECT_DEPENDENCIES.sort
  unless direct_in_podfile == expected_direct
    violations << "Podfile direct dependencies must be #{expected_direct.inspect}; found #{direct_in_podfile.inspect}"
  end
  unless direct_in_lock == expected_direct
    violations << "Podfile.lock direct dependencies must be #{expected_direct.inspect}; found #{direct_in_lock.inspect}"
  end

  root_pods = lock_root_pods(lock).sort
  expected_roots = EXPECTED_ROOT_PODS.sort
  unless root_pods == expected_roots
    violations << "Podfile.lock root pods must be #{expected_roots.inspect}; found #{root_pods.inspect}"
  end

  manifest_path = repository_root.join("Pods/Manifest.lock")
  manifest_status = "absent"
  if manifest_path.file?
    manifest_status = "verified"
    manifest = read_file(manifest_path)
    violations << "Pods/Manifest.lock differs from Podfile.lock" unless manifest == lock
  end

  workspace = read_file(repository_root.join("MissCat.xcworkspace/contents.xcworkspacedata"))
  unless workspace.include?('location = "group:MissCat.xcodeproj"') &&
         workspace.include?('location = "group:Pods/Pods.xcodeproj"')
    violations << "workspace must reference both MissCat.xcodeproj and Pods/Pods.xcodeproj"
  end

  objects = project_objects(project_path)
  _target_id, target = objects.find do |_identifier, object|
    object["isa"] == "PBXNativeTarget" && object["name"] == target_name
  end
  raise BoundaryError, "PBX target was not found: #{target_name}" unless target

  configuration_list = objects.fetch(target.fetch("buildConfigurationList"))
  configurations = Array(configuration_list["buildConfigurations"]).each_with_object({}) do |identifier, result|
    configuration = objects.fetch(identifier)
    result[configuration.fetch("name")] = configuration
  end
  unless configurations.keys.sort == EXPECTED_CONFIGURATIONS.sort
    violations << "#{target_name} configurations must be #{EXPECTED_CONFIGURATIONS.inspect}; found #{configurations.keys.sort.inspect}"
  end

  EXPECTED_CONFIGURATIONS.each do |name|
    configuration = configurations[name]
    next unless configuration

    settings = configuration.fetch("buildSettings", {})
    search_paths = Array(settings["FRAMEWORK_SEARCH_PATHS"])
    unless search_paths == EXPECTED_SEARCH_PATHS
      violations << "#{name} FRAMEWORK_SEARCH_PATHS must contain only $(inherited); found #{search_paths.inspect}"
    end

    ldflags = Array(settings["OTHER_LDFLAGS"])
    unless ldflags == expected_ldflags
      violations << "#{name} OTHER_LDFLAGS must preserve only inherited and current frameworks; found #{ldflags.inspect}"
    end

    base_reference_id = configuration["baseConfigurationReference"]
    base_reference = base_reference_id && objects[base_reference_id]
    expected_path = "Target Support Files/Pods-MissCat/Pods-MissCat.#{name.downcase}.xcconfig"
    unless base_reference && base_reference["path"] == expected_path
      found = base_reference && base_reference["path"]
      violations << "#{name} base configuration must be #{expected_path}; found #{found.inspect}"
    end
  end

  build_phases = Array(target["buildPhases"]).map { |identifier| objects.fetch(identifier) }
  pod_phase_names = build_phases.select do |phase|
    phase["isa"] == "PBXShellScriptBuildPhase" && phase["name"].to_s.start_with?("[CP]")
  end.map { |phase| phase["name"] }.sort
  unless pod_phase_names == EXPECTED_POD_PHASES.sort
    violations << "CocoaPods build phases must be #{EXPECTED_POD_PHASES.inspect}; found #{pod_phase_names.inspect}"
  end

  framework_paths = build_phases.select do |phase|
    phase["isa"] == "PBXFrameworksBuildPhase"
  end.flat_map do |phase|
    Array(phase["files"]).map do |build_file_id|
      build_file = objects.fetch(build_file_id)
      file_reference = objects[build_file["fileRef"]]
      file_reference && file_reference["path"]
    end
  end.compact.sort
  unless framework_paths == ["Pods_MissCat.framework"]
    violations << "app Frameworks phase must contain only Pods_MissCat.framework; found #{framework_paths.inspect}"
  end

  if violations.empty?
    puts "Pod linkage boundary verified: target=#{target_name} direct=#{expected_direct.length} roots=#{expected_roots.length} manifest=#{manifest_status}"
    exit 0
  end

  violations.each { |violation| warn "Pod linkage boundary violation: #{violation}" }
  exit 1
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 64
rescue BoundaryError, KeyError => error
  warn "Pod linkage boundary verification failed: #{error.message}"
  exit 2
end
