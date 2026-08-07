#!/usr/bin/env ruby

require "json"
require "open3"
require "optparse"
require "pathname"

EXPECTED_CONFIGURATIONS = %w[Debug Release].freeze
FORBIDDEN_ROOT_ARTIFACTS = %w[
  Podfile
  Podfile.lock
  Pods
  MissCat/Resources/ThirdPartyAcknowledgements.plist
  config/third-party-acknowledgements.lock.json
].freeze
FORBIDDEN_PROJECT_TOKENS = %w[
  Pods_MissCat.framework
  Pods-MissCat
  PODS_ROOT
  PODS_PODFILE_DIR_PATH
  ThirdPartyAcknowledgements
  Firebase
  MisskeyKit
  Starscream
].freeze

class BoundaryError < StandardError; end

def read_file(path)
  File.read(path, encoding: "UTF-8")
rescue Errno::ENOENT
  raise BoundaryError, "required file is missing: #{path}"
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

options = {}
parser = OptionParser.new do |arguments|
  arguments.banner = "usage: scripts/verify-pod-linkage-boundary.rb [options]"
  arguments.on("--repository-root PATH", "repository root") { |value| options[:repository_root] = value }
  arguments.on("--project PATH", "project.pbxproj path") { |value| options[:project] = value }
  arguments.on("--target NAME", "app target (default: MissCat)") { |value| options[:target] = value }
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
    File.expand_path(options[:project] || repository_root.join("MissCat.xcodeproj/project.pbxproj"))
  )
  target_name = options[:target] || "MissCat"
  violations = []

  FORBIDDEN_ROOT_ARTIFACTS.each do |relative_path|
    path = repository_root.join(relative_path)
    violations << "forbidden dependency artifact exists: #{relative_path}" if path.exist?
  end

  project_source = read_file(project_path)
  FORBIDDEN_PROJECT_TOKENS.each do |token|
    violations << "project retains dependency reference: #{token}" if project_source.include?(token)
  end
  violations << "project retains a CocoaPods build phase" if project_source.include?("[CP]")

  workspace = read_file(repository_root.join("MissCat.xcworkspace/contents.xcworkspacedata"))
  unless workspace.include?('location = "group:MissCat.xcodeproj"')
    violations << "workspace must reference MissCat.xcodeproj"
  end
  if workspace.match?(/Pods|Podfile|\.xcconfig/i)
    violations << "workspace retains a CocoaPods reference"
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

    violations << "#{name} base configuration must be absent" if configuration.key?("baseConfigurationReference")
    settings = configuration.fetch("buildSettings", {})
    violations << "#{name} FRAMEWORK_SEARCH_PATHS must be absent" if settings.key?("FRAMEWORK_SEARCH_PATHS")
    violations << "#{name} OTHER_LDFLAGS must be absent" if settings.key?("OTHER_LDFLAGS")
  end

  build_phases = Array(target["buildPhases"]).map { |identifier| objects.fetch(identifier) }
  shell_phases = build_phases.select { |phase| phase["isa"] == "PBXShellScriptBuildPhase" }
  violations << "app target must not contain shell dependency phases" unless shell_phases.empty?

  framework_paths = build_phases.select do |phase|
    phase["isa"] == "PBXFrameworksBuildPhase"
  end.flat_map do |phase|
    Array(phase["files"]).each_with_object([]) do |build_file_id, paths|
      build_file = objects.fetch(build_file_id)
      file_reference = objects[build_file["fileRef"]]
      path = file_reference && (file_reference["path"] || file_reference["name"])
      paths << path if path
    end
  end
  unless framework_paths.empty?
    violations << "app Frameworks phase must be empty; found #{framework_paths.sort.inspect}"
  end

  if violations.empty?
    puts "Pod linkage boundary verified: target=#{target_name} direct=0 roots=0 references=0"
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
