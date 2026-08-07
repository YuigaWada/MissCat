#!/usr/bin/env ruby

require "json"
require "open3"
require "optparse"
require "pathname"
require "set"

require_relative "verify-swiftui-framework-ratio"

SOURCE_BOUNDARY_SCHEMA_VERSION = 1
SHIPPING_TARGETS = Set.new(%w[MissCat MissCatShare]).freeze
SHIPPING_UIKIT_ALLOWLIST = Set.new([
  "MissCat/Others/App/AppDelegate.swift",
  "MissCat/Others/Platform/MissCatSystemClipboardWriter.swift",
  "MissCatShare/ShareViewController.swift"
]).freeze
RETIRED_PREFIXES = [
  "MissCat/Entity/",
  "MissCat/MFMEngine/",
  "MissCat/Model/",
  "MissCat/View/",
  "MissCat/ViewModel/"
].freeze
RETIRED_EXACT_PATHS = Set.new([
  "MissCat/Others/App/SceneDelegate.swift"
]).freeze
MANAGED_SOURCE_EXCLUDED_COMPONENTS = Set.new(%w[
  Pods
  Vendor
  Vendors
  vendor
  vendors
  ThirdParty
  Third-Party
  third_party
  third-party
  Generated
  generated
]).freeze
IMPORT_PATTERN = /^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)\b/.freeze

class NativeTargetCatalog
  def initialize(project_path)
    @project_path = project_path
  end

  def names
    objects.values
      .select { |object| object["isa"] == "PBXNativeTarget" }
      .map { |object| object["name"] }
      .tap do |names|
        invalid = names.reject { |name| name.is_a?(String) && !name.empty? }
        raise VerificationError, "PBX native target has no valid name" unless invalid.empty?
        raise VerificationError, "PBX project has no native targets" if names.empty?
        raise VerificationError, "PBX native target names are not unique" unless names.uniq.length == names.length
      end
      .sort
  end

  private

  def objects
    stdout, stderr, status = Open3.capture3(
      "/usr/bin/plutil",
      "-convert",
      "json",
      "-o",
      "-",
      @project_path.to_s
    )
    unless status.success?
      detail = stderr.strip.empty? ? "plutil exited #{status.exitstatus}" : stderr.strip
      raise VerificationError, "PBX project could not be parsed: #{detail}"
    end

    JSON.parse(stdout).fetch("objects")
  rescue JSON::ParserError, KeyError => error
    raise VerificationError, "PBX project JSON is invalid: #{error.message}"
  end
end

class TrackedRepositoryFiles
  def initialize(repository_root)
    @repository_root = repository_root
  end

  def matching(*pathspecs)
    stdout, stderr, status = Open3.capture3(
      "/usr/bin/git",
      "-C",
      @repository_root.to_s,
      "ls-files",
      "-z",
      "--",
      *pathspecs
    )
    unless status.success?
      detail = stderr.strip.empty? ? "git exited #{status.exitstatus}" : stderr.strip
      raise VerificationError, "tracked files could not be enumerated: #{detail}"
    end

    stdout.split("\0").reject(&:empty?).sort
  end
end

class RetiredSourceManifest
  attr_reader :paths

  def initialize(path)
    parsed = JSON.parse(File.read(path, encoding: "UTF-8"))
    unless parsed["schema_version"] == SOURCE_BOUNDARY_SCHEMA_VERSION
      raise VerificationError, "unsupported retired-source manifest schema"
    end

    entries = parsed.fetch("files")
    unless entries.is_a?(Array) && entries.all? { |entry| entry.is_a?(Hash) }
      raise VerificationError, "retired-source manifest files must be an array of objects"
    end

    @paths = entries.map do |entry|
      source_path = entry.fetch("path")
      unless safe_relative_path?(source_path)
        raise VerificationError, "retired-source manifest has an unsafe path: #{source_path.inspect}"
      end
      source_path
    end
    unless @paths.uniq.length == @paths.length
      raise VerificationError, "retired-source manifest contains duplicate paths"
    end
    declared_count = parsed.fetch("retired_unowned_count")
    unless declared_count == @paths.length
      raise VerificationError, "retired-source manifest count does not match its file list"
    end
  rescue Errno::ENOENT
    raise VerificationError, "retired-source manifest was not found: #{path}"
  rescue JSON::ParserError, KeyError => error
    raise VerificationError, "retired-source manifest JSON is invalid: #{error.message}"
  end

  private

  def safe_relative_path?(path)
    return false unless path.is_a?(String) && !path.empty?

    pathname = Pathname.new(path)
    !pathname.absolute? && !pathname.each_filename.include?("..")
  end
end

class TrackedSourceBoundary
  attr_reader :result

  def initialize(project_path:, repository_root:, manifest_path:)
    @project_path = project_path
    @repository_root = repository_root
    @manifest_path = manifest_path
    @result = verify
  end

  private

  def verify
    tracked = TrackedRepositoryFiles.new(@repository_root)
    tracked_swift = tracked.matching("*.swift")
    managed_swift, excluded_swift = tracked_swift.partition { |path| managed_source?(path) }
    tracked_ib = tracked.matching("*.storyboard", "*.xib")

    targets = NativeTargetCatalog.new(@project_path).names
    target_membership = targets.to_h do |target|
      paths = ProjectSources.new(
        project_path: @project_path,
        repository_root: @repository_root,
        target_name: target
      ).paths.map { |path| relative_path(path) }
      [target, paths]
    end

    owners = Hash.new { |hash, key| hash[key] = [] }
    target_membership.each do |target, paths|
      paths.each { |path| owners[path] << target }
    end
    owned_swift = owners.keys.sort
    unowned_swift = managed_swift.reject { |path| owners.key?(path) }
    retired_manifest_paths = RetiredSourceManifest.new(@manifest_path).paths.to_set

    violations = []
    tracked_ib.each do |path|
      violations << "tracked Interface Builder artifact is forbidden: #{path}"
    end
    unowned_swift.each do |path|
      violations << "tracked Swift source has no PBX native target membership: #{path}"
    end

    retired_reappearances = managed_swift.select { |path| retired_manifest_paths.include?(path) }
    retired_reappearances.each do |path|
      violations << "retired source path is tracked again: #{path}"
    end

    retired_pattern_paths = managed_swift.select { |path| retired_pattern?(path) }
    retired_pattern_paths.each do |path|
      violations << "retired source pattern is forbidden: #{path}"
    end

    rx_or_polio = []
    uikit_imports = []
    managed_swift.each do |path|
      imports = imports_for(path)
      legacy_imports = imports.select { |name| name.start_with?("Rx") || name == "PolioPager" }
      unless legacy_imports.empty?
        rx_or_polio << { "path" => path, "imports" => legacy_imports.sort }
        violations << "retired dependency import is forbidden in #{path}: #{legacy_imports.sort.join(", ")}"
      end
      uikit_imports << path if imports.include?("UIKit")
    end

    shipping_uikit_imports = uikit_imports.select do |path|
      !(owners[path].to_set & SHIPPING_TARGETS).empty?
    end
    unexpected_shipping_uikit = shipping_uikit_imports.reject do |path|
      SHIPPING_UIKIT_ALLOWLIST.include?(path)
    end
    unexpected_shipping_uikit.each do |path|
      violations << "UIKit import is outside the active shipping OS-boundary allowlist: #{path}"
    end
    missing_uikit_boundaries = SHIPPING_UIKIT_ALLOWLIST.reject do |path|
      shipping_uikit_imports.include?(path)
    end.to_a.sort
    missing_uikit_boundaries.each do |path|
      violations << "active shipping UIKit OS boundary is missing: #{path}"
    end

    target_summaries = target_membership.to_h do |target, paths|
      [target, { "count" => paths.length, "paths" => paths }]
    end
    {
      "schema_version" => SOURCE_BOUNDARY_SCHEMA_VERSION,
      "passed" => violations.empty?,
      "counts" => {
        "native_targets" => targets.length,
        "tracked_swift" => tracked_swift.length,
        "managed_swift" => managed_swift.length,
        "excluded_swift" => excluded_swift.length,
        "owned_unique_swift" => owned_swift.length,
        "unowned_swift" => unowned_swift.length,
        "tracked_ib_artifacts" => tracked_ib.length,
        "retired_reappearances" => retired_reappearances.length,
        "retired_pattern_paths" => retired_pattern_paths.length,
        "rx_or_polio_sources" => rx_or_polio.length,
        "shipping_uikit_imports" => shipping_uikit_imports.length
      },
      "targets" => target_summaries,
      "managed_exclusions" => excluded_swift,
      "unowned_swift" => unowned_swift,
      "tracked_ib_artifacts" => tracked_ib,
      "retired_reappearances" => retired_reappearances,
      "retired_pattern_paths" => retired_pattern_paths,
      "rx_or_polio_sources" => rx_or_polio,
      "uikit_imports" => uikit_imports,
      "shipping_uikit_imports" => shipping_uikit_imports,
      "shipping_uikit_allowlist" => SHIPPING_UIKIT_ALLOWLIST.to_a.sort,
      "violations" => violations.sort
    }
  end

  def relative_path(path)
    expanded = path.realpath
    relative = expanded.relative_path_from(@repository_root).to_s
    unless managed_source?(relative)
      raise VerificationError, "PBX native target owns an excluded or unmanaged Swift source: #{relative}"
    end
    relative
  rescue ArgumentError
    raise VerificationError, "PBX Swift source escapes repository root: #{path}"
  end

  def managed_source?(path)
    path.split("/").none? { |component| MANAGED_SOURCE_EXCLUDED_COMPONENTS.include?(component) }
  end

  def retired_pattern?(path)
    RETIRED_EXACT_PATHS.include?(path) ||
      RETIRED_PREFIXES.any? { |prefix| path.start_with?(prefix) } ||
      (path.end_with?("ViewController.swift") && path != "MissCatShare/ShareViewController.swift") ||
      path.end_with?("ViewModel.swift")
  end

  def imports_for(relative_path)
    source = File.read(@repository_root.join(relative_path), encoding: "UTF-8")
    source.scan(IMPORT_PATTERN).flatten.uniq
  rescue ArgumentError => error
    raise VerificationError, "Swift source is not valid UTF-8 (#{relative_path}): #{error.message}"
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  parser = OptionParser.new do |arguments|
    arguments.banner = "usage: scripts/verify-tracked-swift-source-boundary.rb [options]"
    arguments.on("--project PATH", "Xcode project directory or project.pbxproj") { |value| options[:project] = value }
    arguments.on("--repository-root PATH", "repository root (defaults from project)") { |value| options[:repository_root] = value }
    arguments.on("--manifest PATH", "retired-source checksum manifest") { |value| options[:manifest] = value }
    arguments.on("-h", "--help", "show this help") do
      puts arguments
      exit 0
    end
  end

  begin
    parser.parse!
    raise OptionParser::InvalidOption, ARGV.join(" ") unless ARGV.empty?

    script_root = Pathname.new(File.expand_path("..", __dir__))
    project_path = normalized_project_path(options[:project] || script_root.join("MissCat.xcodeproj"))
    repository_root = Pathname.new(
      File.expand_path(options[:repository_root] || project_path.dirname.dirname)
    ).realpath
    manifest_path = Pathname.new(
      File.expand_path(
        options[:manifest] || repository_root.join("docs/retired-swift-source-manifest.json")
      )
    )

    result = TrackedSourceBoundary.new(
      project_path: project_path,
      repository_root: repository_root,
      manifest_path: manifest_path
    ).result
    puts JSON.pretty_generate(result)
    exit(result.fetch("passed") ? 0 : 1)
  rescue OptionParser::ParseError => error
    warn error.message
    warn parser
    exit 64
  rescue VerificationError, Errno::ENOENT => error
    warn "tracked Swift source boundary verification failed: #{error.message}"
    exit 2
  end
end
