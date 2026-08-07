#!/usr/bin/env ruby

require "json"
require "open3"
require "optparse"
require "pathname"
require "set"

SCHEMA_VERSION = 1
DEFAULT_TARGET = "MissCat"
RATCHET_MAXIMUM_KEYS = %w[
  uikit_only
  hybrid
  rx_files
  polio_files
  legacy_loader_files
  legacy_loader_refs
  tracked_ib_artifacts
].freeze
COMPLETE_ZERO_KEYS = RATCHET_MAXIMUM_KEYS.freeze
LEGACY_LOADER_PATTERN = /\b(?:UIStoryboard|UINib)\b|\binstantiateViewController\s*\(|\bnibName\s*:/.freeze

class VerificationError < StandardError; end

class ProjectSources
  def initialize(project_path:, repository_root:, target_name:)
    @project_path = project_path
    @repository_root = repository_root
    @target_name = target_name
  end

  def paths
    objects = project_objects
    target_id, target = objects.find do |_id, object|
      object["isa"] == "PBXNativeTarget" && object["name"] == @target_name
    end
    raise VerificationError, "PBX target was not found: #{@target_name}" unless target_id

    source_phase_ids = Array(target["buildPhases"]).select do |identifier|
      objects.fetch(identifier, {})["isa"] == "PBXSourcesBuildPhase"
    end
    raise VerificationError, "PBX target has no sources build phase: #{@target_name}" if source_phase_ids.empty?

    parent_by_child = {}
    objects.each do |identifier, object|
      next unless %w[PBXGroup PBXVariantGroup].include?(object["isa"])

      Array(object["children"]).each { |child| parent_by_child[child] = identifier }
    end

    file_reference_ids = source_phase_ids.flat_map do |phase_id|
      Array(objects.fetch(phase_id)["files"]).map do |build_file_id|
        build_file = objects.fetch(build_file_id) do
          raise VerificationError, "PBX source build file is missing: #{build_file_id}"
        end
        build_file["fileRef"] || raise(
          VerificationError,
          "PBX source build file has no file reference: #{build_file_id}"
        )
      end
    end

    resolved = file_reference_ids.each_with_object([]) do |file_reference_id, paths|
      object = objects.fetch(file_reference_id) do
        raise VerificationError, "PBX source file reference is missing: #{file_reference_id}"
      end
      next unless File.extname(object["path"].to_s).casecmp(".swift").zero?

      paths << resolve_file_reference(
        file_reference_id,
        objects: objects,
        parent_by_child: parent_by_child
      )
    end

    duplicates = resolved.group_by(&:to_s).select { |_path, entries| entries.length > 1 }.keys
    unless duplicates.empty?
      raise VerificationError, "PBX target has duplicate Swift source membership: #{duplicates.sort.join(", ")}"
    end

    resolved.sort_by(&:to_s)
  end

  private

  def project_objects
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

    parsed = JSON.parse(stdout)
    parsed.fetch("objects")
  rescue JSON::ParserError, KeyError => error
    raise VerificationError, "PBX project JSON is invalid: #{error.message}"
  end

  def resolve_file_reference(identifier, objects:, parent_by_child:)
    object = objects.fetch(identifier)
    raw_path = object["path"] || object["name"]
    raise VerificationError, "PBX file reference has no path: #{identifier}" if raw_path.to_s.empty?

    source_tree = object.fetch("sourceTree", "<group>")
    candidate = case source_tree
                when "<group>"
                  group_base(parent_by_child[identifier], objects, parent_by_child).join(raw_path)
                when "SOURCE_ROOT"
                  @repository_root.join(raw_path)
                when "<absolute>"
                  Pathname.new(raw_path)
                else
                  raise VerificationError,
                        "unsupported PBX source tree #{source_tree.inspect} for #{raw_path}"
                end

    expanded = Pathname.new(File.expand_path(candidate.to_s))
    repository_prefix = @repository_root.to_s + File::SEPARATOR
    unless expanded.to_s.start_with?(repository_prefix)
      raise VerificationError, "PBX Swift source escapes repository root: #{expanded}"
    end
    raise VerificationError, "PBX Swift source is missing: #{expanded}" unless expanded.file?

    expanded
  end

  def group_base(identifier, objects, parent_by_child, visiting = Set.new)
    return @repository_root unless identifier
    raise VerificationError, "PBX group hierarchy contains a cycle at #{identifier}" if visiting.include?(identifier)

    visiting = visiting.dup.add(identifier)
    object = objects.fetch(identifier) do
      raise VerificationError, "PBX parent group is missing: #{identifier}"
    end
    source_tree = object.fetch("sourceTree", "<group>")
    raw_path = object["path"]
    parent_base = case source_tree
                  when "<group>"
                    group_base(parent_by_child[identifier], objects, parent_by_child, visiting)
                  when "SOURCE_ROOT"
                    @repository_root
                  when "<absolute>"
                    Pathname.new(File::SEPARATOR)
                  else
                    raise VerificationError,
                          "unsupported PBX group source tree #{source_tree.inspect} for #{identifier}"
                  end
    raw_path.to_s.empty? ? parent_base : parent_base.join(raw_path)
  end
end

class Metric
  attr_reader :counts, :progress

  def initialize(source_paths:, repository_root:)
    @source_paths = source_paths
    @repository_root = repository_root
    @counts = calculate_counts
    @progress = calculate_progress
  end

  private

  def calculate_counts
    categories = Hash.new(0)
    rx_files = 0
    polio_files = 0
    legacy_loader_files = 0
    legacy_loader_refs = 0

    @source_paths.each do |path|
      source = File.read(path, encoding: "UTF-8")
      imports = source.scan(/^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)\b/).flatten.to_set
      has_uikit = imports.include?("UIKit")
      has_swiftui = imports.include?("SwiftUI")
      category = if has_uikit && has_swiftui
                   "hybrid"
                 elsif has_uikit
                   "uikit_only"
                 elsif has_swiftui
                   "swiftui_only"
                 else
                   "neutral"
                 end
      categories[category] += 1
      rx_files += 1 if imports.any? { |name| name.start_with?("Rx") }
      polio_files += 1 if imports.include?("PolioPager")

      loader_references = source.each_line.count do |line|
        stripped = line.lstrip
        !stripped.start_with?("//") && stripped.match?(LEGACY_LOADER_PATTERN)
      end
      if loader_references.positive?
        legacy_loader_files += 1
        legacy_loader_refs += loader_references
      end
    rescue ArgumentError => error
      raise VerificationError, "Swift source is not valid UTF-8 (#{path}): #{error.message}"
    end

    {
      "total_swift" => @source_paths.length,
      "uikit_only" => categories["uikit_only"],
      "swiftui_only" => categories["swiftui_only"],
      "hybrid" => categories["hybrid"],
      "neutral" => categories["neutral"],
      "rx_files" => rx_files,
      "polio_files" => polio_files,
      "legacy_loader_files" => legacy_loader_files,
      "legacy_loader_refs" => legacy_loader_refs,
      "tracked_ib_artifacts" => tracked_ib_artifacts
    }
  end

  def tracked_ib_artifacts
    stdout, stderr, status = Open3.capture3(
      "/usr/bin/git",
      "-C",
      @repository_root.to_s,
      "ls-files",
      "-z",
      "--",
      "*.storyboard",
      "*.xib"
    )
    unless status.success?
      detail = stderr.strip.empty? ? "git exited #{status.exitstatus}" : stderr.strip
      raise VerificationError, "tracked IB artifacts could not be enumerated: #{detail}"
    end

    stdout.split("\0").reject(&:empty?).length
  end

  def calculate_progress
    denominator = counts.fetch("uikit_only") + counts.fetch("swiftui_only") + counts.fetch("hybrid")
    numerator = counts.fetch("swiftui_only")
    basis_points = denominator.zero? ? 10_000 : (numerator * 10_000) / denominator
    {
      "numerator" => numerator,
      "denominator" => denominator,
      "basis_points" => basis_points,
      "percent" => (basis_points / 100.0).round(2)
    }
  end
end

def normalized_project_path(raw_path)
  path = Pathname.new(File.expand_path(raw_path))
  path = path.join("project.pbxproj") if path.directory? && path.extname == ".xcodeproj"
  raise VerificationError, "PBX project was not found: #{path}" unless path.file?

  path
end

def load_baseline(path, target_name)
  parsed = JSON.parse(File.read(path, encoding: "UTF-8"))
  raise VerificationError, "unsupported baseline schema" unless parsed["schema_version"] == SCHEMA_VERSION
  raise VerificationError, "baseline target does not match #{target_name}" unless parsed["target"] == target_name

  counts = parsed.fetch("counts")
  required = %w[
    total_swift uikit_only swiftui_only hybrid neutral rx_files polio_files
    legacy_loader_files legacy_loader_refs tracked_ib_artifacts
  ]
  missing = required.reject { |key| counts[key].is_a?(Integer) && counts[key] >= 0 }
  unless missing.empty?
    raise VerificationError, "baseline has missing or invalid counts: #{missing.join(", ")}"
  end
  classified_total = counts.values_at("uikit_only", "swiftui_only", "hybrid", "neutral").sum
  unless classified_total == counts["total_swift"]
    raise VerificationError, "baseline Swift categories do not sum to total_swift"
  end

  counts
rescue Errno::ENOENT
  raise VerificationError, "baseline was not found: #{path}"
rescue JSON::ParserError, KeyError => error
  raise VerificationError, "baseline JSON is invalid: #{error.message}"
end

def progress_for(counts)
  denominator = counts.fetch("uikit_only") + counts.fetch("swiftui_only") + counts.fetch("hybrid")
  numerator = counts.fetch("swiftui_only")
  [numerator, denominator]
end

def progress_regressed?(current_counts, baseline_counts)
  current_numerator, current_denominator = progress_for(current_counts)
  baseline_numerator, baseline_denominator = progress_for(baseline_counts)
  return false if baseline_denominator.zero?
  return true if current_denominator.zero?

  current_numerator * baseline_denominator < baseline_numerator * current_denominator
end

if $PROGRAM_NAME == __FILE__
  options = {
    target: DEFAULT_TARGET,
    require_complete: false
  }

parser = OptionParser.new do |arguments|
  arguments.banner = <<~USAGE
    usage: scripts/verify-swiftui-framework-ratio.rb [options]

    Default mode verifies that shipping-target framework debt has not regressed
    from the checked-in baseline. --require-complete additionally requires every
    legacy framework/loader/IB count to be zero.
  USAGE
  arguments.on("--project PATH", "Xcode project directory or project.pbxproj") { |value| options[:project] = value }
  arguments.on("--repository-root PATH", "repository root (defaults from project)") { |value| options[:repository_root] = value }
  arguments.on("--target NAME", "PBX native target (default: #{DEFAULT_TARGET})") { |value| options[:target] = value }
  arguments.on("--baseline PATH", "ratchet baseline JSON") { |value| options[:baseline] = value }
  arguments.on("--require-complete", "require a zero-legacy shipping target") { options[:require_complete] = true }
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
  )
  baseline_path = Pathname.new(
    File.expand_path(
      options[:baseline] || repository_root.join("config/swiftui-framework-ratio-baseline.json")
    )
  )

  source_paths = ProjectSources.new(
    project_path: project_path,
    repository_root: repository_root,
    target_name: options[:target]
  ).paths
  metric = Metric.new(source_paths: source_paths, repository_root: repository_root)
  baseline_counts = load_baseline(baseline_path, options[:target])

  violations = []
  RATCHET_MAXIMUM_KEYS.each do |key|
    current = metric.counts.fetch(key)
    baseline = baseline_counts.fetch(key)
    violations << "#{key} increased from #{baseline} to #{current}" if current > baseline
  end
  if progress_regressed?(metric.counts, baseline_counts)
    current_numerator, current_denominator = progress_for(metric.counts)
    baseline_numerator, baseline_denominator = progress_for(baseline_counts)
    violations << "pure_swiftui_progress decreased from #{baseline_numerator}/#{baseline_denominator} to #{current_numerator}/#{current_denominator}"
  end

  if options[:require_complete]
    COMPLETE_ZERO_KEYS.each do |key|
      value = metric.counts.fetch(key)
      violations << "#{key} must be zero for completion (was #{value})" unless value.zero?
    end
  end

  result = {
    "schema_version" => SCHEMA_VERSION,
    "target" => options[:target],
    "mode" => options[:require_complete] ? "require-complete" : "ratchet",
    "counts" => metric.counts,
    "pure_swiftui_progress" => metric.progress,
    "baseline_counts" => baseline_counts,
    "passed" => violations.empty?,
    "violations" => violations
  }
  puts JSON.pretty_generate(result)
  exit(violations.empty? ? 0 : 1)
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 64
rescue VerificationError => error
  warn "SwiftUI framework ratio verification failed: #{error.message}"
  exit 2
end
end
