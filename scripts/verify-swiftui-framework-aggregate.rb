#!/usr/bin/env ruby

require_relative "verify-swiftui-framework-ratio"

AGGREGATE_SCHEMA_VERSION = 1
SHIPPING_TARGETS = [
  { "name" => "MissCat", "role" => "application" },
  { "name" => "MissCatShare", "role" => "share_extension" }
].freeze
AGGREGATE_SUM_KEYS = %w[
  total_swift
  uikit_only
  swiftui_only
  hybrid
  neutral
  rx_files
  polio_files
  legacy_loader_files
  legacy_loader_refs
].freeze
AGGREGATE_COUNT_KEYS = (AGGREGATE_SUM_KEYS + ["tracked_ib_artifacts"]).freeze
TARGET_COMPLETION_DEBT_KEYS = %w[
  rx_files
  polio_files
  legacy_loader_files
  legacy_loader_refs
].freeze

def validated_aggregate_counts(raw_counts, label)
  unless raw_counts.is_a?(Hash)
    raise VerificationError, "#{label} counts must be an object"
  end

  invalid = AGGREGATE_COUNT_KEYS.reject do |key|
    raw_counts[key].is_a?(Integer) && raw_counts[key] >= 0
  end
  unless invalid.empty?
    raise VerificationError, "#{label} has missing or invalid counts: #{invalid.join(", ")}"
  end

  classified_total = raw_counts.values_at("uikit_only", "swiftui_only", "hybrid", "neutral").sum
  unless classified_total == raw_counts.fetch("total_swift")
    raise VerificationError, "#{label} Swift categories do not sum to total_swift"
  end

  raw_counts.slice(*AGGREGATE_COUNT_KEYS)
end

def aggregate_counts_for(target_counts, label: "aggregate")
  aggregate = AGGREGATE_SUM_KEYS.to_h do |key|
    [key, target_counts.sum { |counts| counts.fetch(key) }]
  end
  ib_counts = target_counts.map { |counts| counts.fetch("tracked_ib_artifacts") }.uniq
  unless ib_counts.length == 1
    raise VerificationError, "#{label} target metrics disagree on repository-wide tracked_ib_artifacts"
  end
  aggregate["tracked_ib_artifacts"] = ib_counts.fetch(0)
  validated_aggregate_counts(aggregate, label)
end

def exact_progress_for(counts)
  numerator, denominator = progress_for(counts)
  basis_points = denominator.zero? ? 10_000 : (numerator * 10_000) / denominator
  percent = denominator.zero? ? 100.0 : ((numerator * 100.0) / denominator).round(3)
  {
    "numerator" => numerator,
    "denominator" => denominator,
    "fraction" => "#{numerator}/#{denominator}",
    "basis_points" => basis_points,
    "percent" => percent
  }
end

def load_aggregate_baseline(path)
  parsed = JSON.parse(File.read(path, encoding: "UTF-8"))
  unless parsed["schema_version"] == AGGREGATE_SCHEMA_VERSION
    raise VerificationError, "unsupported aggregate baseline schema"
  end

  raw_targets = parsed.fetch("targets")
  expected_names = SHIPPING_TARGETS.map { |entry| entry.fetch("name") }
  unless raw_targets.is_a?(Hash) && raw_targets.keys.sort == expected_names.sort
    raise VerificationError, "aggregate baseline targets must be exactly: #{expected_names.join(", ")}"
  end

  targets = expected_names.to_h do |target_name|
    target_entry = raw_targets.fetch(target_name)
    unless target_entry.is_a?(Hash)
      raise VerificationError, "baseline #{target_name} must be an object"
    end
    [target_name, validated_aggregate_counts(target_entry.fetch("counts"), "baseline #{target_name}")]
  end
  aggregate_entry = parsed.fetch("aggregate")
  unless aggregate_entry.is_a?(Hash)
    raise VerificationError, "baseline aggregate must be an object"
  end
  aggregate = validated_aggregate_counts(aggregate_entry.fetch("counts"), "baseline aggregate")
  derived_aggregate = aggregate_counts_for(targets.values, label: "derived baseline aggregate")
  unless aggregate == derived_aggregate
    raise VerificationError, "aggregate baseline counts do not equal the sum of target memberships"
  end

  { "targets" => targets, "aggregate" => aggregate }
rescue Errno::ENOENT
  raise VerificationError, "aggregate baseline was not found: #{path}"
rescue JSON::ParserError, KeyError => error
  raise VerificationError, "aggregate baseline JSON is invalid: #{error.message}"
end

def append_ratchet_violations(scope, current_counts, baseline_counts, violations)
  RATCHET_MAXIMUM_KEYS.each do |key|
    current = current_counts.fetch(key)
    baseline = baseline_counts.fetch(key)
    violations << "#{scope}.#{key} increased from #{baseline} to #{current}" if current > baseline
  end
  return unless progress_regressed?(current_counts, baseline_counts)

  current_numerator, current_denominator = progress_for(current_counts)
  baseline_numerator, baseline_denominator = progress_for(baseline_counts)
  violations << "#{scope}.pure_swiftui_progress decreased from #{baseline_numerator}/#{baseline_denominator} to #{current_numerator}/#{current_denominator}"
end

def completion_blockers_for(target_counts, aggregate_counts)
  blockers = []
  app_counts = target_counts.fetch("MissCat")
  app_uikit_debt = app_counts.fetch("uikit_only") + app_counts.fetch("hybrid")
  if app_uikit_debt.positive?
    blockers << {
      "scope" => "MissCat",
      "metrics" => {
        "uikit_only" => app_counts.fetch("uikit_only"),
        "hybrid" => app_counts.fetch("hybrid")
      },
      "reason" => "App shipping target still contains UIKit framework imports; migrate every UIKit-only and UIKit/SwiftUI hybrid source member."
    }
  end

  share_counts = target_counts.fetch("MissCatShare")
  share_uikit_debt = share_counts.fetch("uikit_only") + share_counts.fetch("hybrid")
  if share_uikit_debt.positive?
    blockers << {
      "scope" => "MissCatShare",
      "metrics" => {
        "uikit_only" => share_counts.fetch("uikit_only"),
        "hybrid" => share_counts.fetch("hybrid")
      },
      "reason" => "ShareViewController remains the NSExtensionPrincipalClass UIKit/SwiftUI hybrid boundary; completion requires retiring that principal UIKit bridge."
    }
  end

  target_counts.each do |target_name, counts|
    TARGET_COMPLETION_DEBT_KEYS.each do |key|
      next if counts.fetch(key).zero?

      blockers << {
        "scope" => target_name,
        "metrics" => { key => counts.fetch(key) },
        "reason" => "#{target_name} still contains #{key} migration debt."
      }
    end
  end

  unless aggregate_counts.fetch("tracked_ib_artifacts").zero?
    blockers << {
      "scope" => "aggregate",
      "metrics" => {
        "tracked_ib_artifacts" => aggregate_counts.fetch("tracked_ib_artifacts")
      },
      "reason" => "Git-tracked storyboard or XIB artifacts still exist in the shipping repository."
    }
  end
  blockers
end

options = { require_complete: false }
parser = OptionParser.new do |arguments|
  arguments.banner = <<~USAGE
    usage: scripts/verify-swiftui-framework-aggregate.rb [options]

    Measures the MissCat application and MissCatShare extension from PBX source
    membership, then ratchets both targets and their combined shipping metric.
  USAGE
  arguments.on("--project PATH", "Xcode project directory or project.pbxproj") { |value| options[:project] = value }
  arguments.on("--repository-root PATH", "repository root (defaults from project)") { |value| options[:repository_root] = value }
  arguments.on("--baseline PATH", "aggregate ratchet baseline JSON") { |value| options[:baseline] = value }
  arguments.on("--require-complete", "require every shipping target to be UIKit/Rx/Polio/loader/IB free") { options[:require_complete] = true }
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
      options[:baseline] || repository_root.join("config/swiftui-framework-aggregate-baseline.json")
    )
  )
  baseline = load_aggregate_baseline(baseline_path)

  target_results = {}
  target_counts = {}
  SHIPPING_TARGETS.each do |entry|
    target_name = entry.fetch("name")
    source_paths = ProjectSources.new(
      project_path: project_path,
      repository_root: repository_root,
      target_name: target_name
    ).paths
    metric = Metric.new(source_paths: source_paths, repository_root: repository_root)
    counts = validated_aggregate_counts(metric.counts, target_name)
    target_counts[target_name] = counts
    target_results[target_name] = {
      "role" => entry.fetch("role"),
      "counts" => counts,
      "pure_swiftui_progress" => exact_progress_for(counts),
      "baseline_counts" => baseline.fetch("targets").fetch(target_name)
    }
  end

  aggregate_counts = aggregate_counts_for(target_counts.values)
  violations = []
  target_counts.each do |target_name, counts|
    append_ratchet_violations(
      "targets.#{target_name}",
      counts,
      baseline.fetch("targets").fetch(target_name),
      violations
    )
  end
  append_ratchet_violations(
    "aggregate",
    aggregate_counts,
    baseline.fetch("aggregate"),
    violations
  )

  completion_blockers = options[:require_complete] ? completion_blockers_for(target_counts, aggregate_counts) : []
  violations.concat(
    completion_blockers.map { |blocker| "#{blocker.fetch("scope")} completion blocked: #{blocker.fetch("reason")}" }
  )

  result = {
    "schema_version" => AGGREGATE_SCHEMA_VERSION,
    "scope" => "shipping_targets",
    "mode" => options[:require_complete] ? "require-complete" : "ratchet",
    "targets" => target_results,
    "aggregate" => {
      "counts" => aggregate_counts,
      "pure_swiftui_progress" => exact_progress_for(aggregate_counts),
      "baseline_counts" => baseline.fetch("aggregate")
    },
    "completion_blockers" => completion_blockers,
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
  warn "Aggregate SwiftUI framework verification failed: #{error.message}"
  exit 2
end
