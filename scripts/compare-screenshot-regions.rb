#!/usr/bin/env ruby

# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"

SCHEMA_VERSION = 1
DEFAULT_MAGICK = "/opt/homebrew/bin/magick"
SUMMARY_HEADER = %w[
  region_id owner kind x y width height changed_similarity ssim edge_coverage status detail
].freeze
CAPTURE_KEYS = %w[
  surface_id state appearance device orientation fixture locale content_size visual_ready
].freeze
TOP_LEVEL_KEYS = %w[
  schema_version surface canvas capture thresholds required_region_ids regions
].freeze
CANVAS_KEYS = %w[width height].freeze
THRESHOLD_KEYS = %w[
  changed_similarity ssim action_edge_coverage edge_tolerance_pixels channel_delta amplification
].freeze
REGION_KEYS = %w[id owner kind x y width height].freeze
TOKEN_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
REGION_ID_PATTERN = /\A[a-z0-9][a-z0-9-]*\z/

class InputError < StandardError; end
class ToolError < StandardError; end

def exact_keys!(object, expected, label)
  raise InputError, "#{label} must be an object" unless object.is_a?(Hash)

  actual = object.keys.sort
  expected_sorted = expected.sort
  return if actual == expected_sorted

  missing = expected_sorted - actual
  unexpected = actual - expected_sorted
  details = []
  details << "missing #{missing.join(', ')}" unless missing.empty?
  details << "unexpected #{unexpected.join(', ')}" unless unexpected.empty?
  raise InputError, "invalid #{label} keys (#{details.join('; ')})"
end

def positive_integer!(value, label)
  raise InputError, "#{label} must be a positive integer" unless value.is_a?(Integer) && value.positive?

  value
end

def nonnegative_integer!(value, label)
  raise InputError, "#{label} must be a nonnegative integer" unless value.is_a?(Integer) && value >= 0

  value
end

def number!(value, label)
  raise InputError, "#{label} must be numeric" unless value.is_a?(Numeric) && value.finite?

  value.to_f
end

def token!(value, label, pattern = TOKEN_PATTERN)
  raise InputError, "#{label} must be a canonical token" unless value.is_a?(String) && pattern.match?(value)

  value
end

def run_capture(*command, accepted: [0])
  stdout, stderr, status = Open3.capture3(*command)
  return [stdout, stderr, status.exitstatus] if accepted.include?(status.exitstatus)

  detail = stderr.strip.empty? ? stdout.strip : stderr.strip
  raise ToolError, "command failed (#{status.exitstatus}): #{detail}"
end

def image_dimensions(magick, path)
  stdout, = run_capture(magick, "identify", "-format", "%w %h\n", path)
  lines = stdout.lines.map(&:strip).reject(&:empty?)
  raise InputError, "multi-frame images are not supported: #{path}" unless lines.length == 1
  raise InputError, "invalid image dimensions: #{path}" unless /\A\d+ \d+\z/.match?(lines.first)

  lines.first.split.map(&:to_i)
rescue ToolError => error
  raise InputError, "cannot read image #{path}: #{error.message}"
end

def image_pixel_count(magick, path)
  stdout, = run_capture(
    magick,
    "-precision", "20",
    path,
    "-alpha", "off",
    "-colorspace", "Gray",
    "-threshold", "50%",
    "-format", "%[fx:round(mean*w*h)]",
    "info:"
  )
  numeric = Float(stdout.strip)
  rounded = numeric.round
  raise ToolError, "invalid pixel count: #{stdout.strip}" unless numeric >= 0 && (numeric - rounded).abs < 0.000_001

  rounded
rescue ArgumentError
  raise ToolError, "invalid pixel count: #{stdout.strip}"
end

def normalized_number(value)
  format("%.12g", value.to_f)
end

def relative_artifact(path, root)
  Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
end

def write_report(out_dir, report, rows)
  FileUtils.mkdir_p(out_dir)
  File.write(File.join(out_dir, "summary.json"), JSON.pretty_generate(report) + "\n")
  File.open(File.join(out_dir, "summary.tsv"), "w") do |file|
    file.puts(SUMMARY_HEADER.join("\t"))
    rows.each do |row|
      file.puts(SUMMARY_HEADER.map { |key| row.fetch(key, "") }.join("\t"))
    end
  end
end

def invalid_report(detail, manifest_path, baseline_path, candidate_path)
  {
    "schema_version" => SCHEMA_VERSION,
    "gate" => "timeline_named_regions",
    "status" => "invalid",
    "detail" => detail,
    "manifest" => manifest_path && File.file?(manifest_path) ? {
      "path" => File.basename(manifest_path),
      "sha256" => Digest::SHA256.file(manifest_path).hexdigest
    } : nil,
    "baseline" => baseline_path && File.file?(baseline_path) ? {
      "path" => File.basename(baseline_path),
      "sha256" => Digest::SHA256.file(baseline_path).hexdigest
    } : nil,
    "candidate" => candidate_path && File.file?(candidate_path) ? {
      "path" => File.basename(candidate_path),
      "sha256" => Digest::SHA256.file(candidate_path).hexdigest
    } : nil,
    "regions" => []
  }
end

def validate_manifest!(manifest)
  exact_keys!(manifest, TOP_LEVEL_KEYS, "manifest")
  raise InputError, "unsupported manifest schema_version: #{manifest['schema_version']}" unless manifest["schema_version"] == SCHEMA_VERSION

  token!(manifest["surface"], "surface")

  canvas = manifest["canvas"]
  exact_keys!(canvas, CANVAS_KEYS, "canvas")
  positive_integer!(canvas["width"], "canvas.width")
  positive_integer!(canvas["height"], "canvas.height")

  capture = manifest["capture"]
  exact_keys!(capture, CAPTURE_KEYS, "capture")
  CAPTURE_KEYS.each { |key| token!(capture[key], "capture.#{key}") }
  raise InputError, "capture.surface_id must contain two digits" unless /\A\d{2}\z/.match?(capture["surface_id"])

  thresholds = manifest["thresholds"]
  exact_keys!(thresholds, THRESHOLD_KEYS, "thresholds")
  changed_similarity = number!(thresholds["changed_similarity"], "thresholds.changed_similarity")
  ssim = number!(thresholds["ssim"], "thresholds.ssim")
  edge_coverage = number!(thresholds["action_edge_coverage"], "thresholds.action_edge_coverage")
  raise InputError, "changed similarity threshold must be at least 0.90 and at most 1" unless changed_similarity.between?(0.9, 1.0)
  raise InputError, "SSIM threshold must be at least 0.90 and at most 1" unless ssim.between?(0.9, 1.0)
  raise InputError, "action edge coverage threshold must be at least 0.90 and at most 1" unless edge_coverage.between?(0.9, 1.0)
  raise InputError, "edge tolerance must be exactly two pixels" unless thresholds["edge_tolerance_pixels"] == 2
  channel_delta = nonnegative_integer!(thresholds["channel_delta"], "thresholds.channel_delta")
  raise InputError, "channel delta must not exceed 8" if channel_delta > 8
  amplification = positive_integer!(thresholds["amplification"], "thresholds.amplification")
  raise InputError, "amplification must be between 2 and 8" unless amplification.between?(2, 8)

  required = manifest["required_region_ids"]
  raise InputError, "required_region_ids must be a nonempty array" unless required.is_a?(Array) && !required.empty?
  required.each { |id| token!(id, "required region id", REGION_ID_PATTERN) }
  duplicate_required = required.group_by(&:itself).find { |_id, occurrences| occurrences.length > 1 }&.first
  raise InputError, "duplicate required region id: #{duplicate_required}" if duplicate_required

  regions = manifest["regions"]
  raise InputError, "regions must be a nonempty array" unless regions.is_a?(Array) && !regions.empty?
  seen = {}
  regions.each_with_index do |region, index|
    exact_keys!(region, REGION_KEYS, "regions[#{index}]")
    id = token!(region["id"], "regions[#{index}].id", REGION_ID_PATTERN)
    raise InputError, "duplicate region id: #{id}" if seen[id]
    seen[id] = true

    raise InputError, "invalid region owner for #{id}" unless %w[app system].include?(region["owner"])
    raise InputError, "invalid region kind for #{id}" unless %w[content action].include?(region["kind"])
    x = nonnegative_integer!(region["x"], "#{id}.x")
    y = nonnegative_integer!(region["y"], "#{id}.y")
    width = positive_integer!(region["width"], "#{id}.width")
    height = positive_integer!(region["height"], "#{id}.height")
    if x + width > canvas["width"] || y + height > canvas["height"]
      raise InputError, "region is out of canvas bounds: #{id}"
    end
  end

  app_ids = regions.select { |region| region["owner"] == "app" }.map { |region| region["id"] }
  missing = required - app_ids
  extra = app_ids - required
  raise InputError, "missing required regions: #{missing.join(', ')}" unless missing.empty?
  raise InputError, "unlisted app-owned regions: #{extra.join(', ')}" unless extra.empty?
  raise InputError, "timeline manifest must contain an app-owned action region" unless regions.any? { |region| region["owner"] == "app" && region["kind"] == "action" }
end

def generate_amplified_artifacts(magick, region_dir, amplification)
  percent = "#{amplification * 100}%"
  {
    "diff_amplified" => ["diff-heatmap.png", "diff-amplified.png"],
    "side_by_side_amplified" => ["side-by-side.png", "side-by-side-amplified.png"]
  }.transform_values do |source_name, output_name|
    source = File.join(region_dir, source_name)
    output = File.join(region_dir, output_name)
    run_capture(magick, source, "-filter", "point", "-resize", percent, "-strip", output)
    output
  end
end

def edge_coverage(magick, baseline_crop, candidate_crop, region_dir, tolerance, amplification)
  baseline_edges = File.join(region_dir, "baseline-edges.png")
  candidate_edges = File.join(region_dir, "candidate-edges.png")
  baseline_dilated = File.join(region_dir, ".baseline-edges-dilated.png")
  candidate_dilated = File.join(region_dir, ".candidate-edges-dilated.png")
  baseline_matches = File.join(region_dir, ".baseline-edge-matches.png")
  candidate_matches = File.join(region_dir, ".candidate-edge-matches.png")
  baseline_color = File.join(region_dir, ".baseline-edge-color.png")
  candidate_color = File.join(region_dir, ".candidate-edge-color.png")
  edge_artifact = File.join(region_dir, "edge-coverage-amplified.png")

  [[baseline_crop, baseline_edges], [candidate_crop, candidate_edges]].each do |source, output|
    run_capture(
      magick,
      source,
      "-alpha", "off",
      "-colorspace", "Gray",
      "-edge", "1",
      "-threshold", "10%",
      "-type", "bilevel",
      "-strip",
      output
    )
  end
  run_capture(magick, baseline_edges, "-morphology", "Dilate", "Disk:#{tolerance}", baseline_dilated)
  run_capture(magick, candidate_edges, "-morphology", "Dilate", "Disk:#{tolerance}", candidate_dilated)
  run_capture(magick, baseline_edges, candidate_dilated, "-compose", "Multiply", "-composite", baseline_matches)
  run_capture(magick, candidate_edges, baseline_dilated, "-compose", "Multiply", "-composite", candidate_matches)

  baseline_count = image_pixel_count(magick, baseline_edges)
  candidate_count = image_pixel_count(magick, candidate_edges)
  baseline_match_count = image_pixel_count(magick, baseline_matches)
  candidate_match_count = image_pixel_count(magick, candidate_matches)
  baseline_coverage = baseline_count.zero? ? 0.0 : baseline_match_count.to_f / baseline_count
  candidate_coverage = candidate_count.zero? ? 0.0 : candidate_match_count.to_f / candidate_count
  coverage = [baseline_coverage, candidate_coverage].min

  run_capture(magick, baseline_edges, "-fill", "#ff0055", "-opaque", "white", baseline_color)
  run_capture(magick, candidate_edges, "-fill", "#00d4ff", "-opaque", "white", candidate_color)
  run_capture(
    magick,
    baseline_color,
    candidate_color,
    "-compose", "screen",
    "-composite",
    "-filter", "point",
    "-resize", "#{amplification * 100}%",
    "-strip",
    edge_artifact
  )

  [baseline_edges, candidate_edges, baseline_dilated, candidate_dilated,
   baseline_matches, candidate_matches, baseline_color, candidate_color].each do |path|
    FileUtils.rm_f(path) if File.basename(path).start_with?(".")
  end

  {
    "coverage" => coverage,
    "baseline_coverage" => baseline_coverage,
    "candidate_coverage" => candidate_coverage,
    "baseline_edge_pixels" => baseline_count,
    "candidate_edge_pixels" => candidate_count,
    "artifact" => edge_artifact
  }
end

options = {
  magick: DEFAULT_MAGICK,
  manifest: nil,
  out: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: scripts/compare-screenshot-regions.sh --manifest FILE [--out DIR] BASELINE.png CANDIDATE.png"
  opts.on("--manifest FILE", "Versioned named-region manifest") { |value| options[:manifest] = value }
  opts.on("--out DIR", "Artifact directory") { |value| options[:out] = value }
  opts.on("--magick PATH", "ImageMagick executable") { |value| options[:magick] = value }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end

out_dir = nil
manifest_path = nil
baseline_path = nil
candidate_path = nil

begin
  remaining = parser.parse(ARGV)
  raise InputError, "--manifest is required" unless options[:manifest]
  raise InputError, "expected baseline and candidate PNG paths" unless remaining.length == 2

  manifest_path = File.realpath(options[:manifest])
  baseline_path = File.realpath(remaining[0])
  candidate_path = File.realpath(remaining[1])
  raise InputError, "ImageMagick executable is unavailable: #{options[:magick]}" unless File.executable?(options[:magick])

  if options[:out]
    FileUtils.mkdir_p(options[:out])
    out_dir = File.realpath(options[:out])
  else
    stem = File.basename(candidate_path, File.extname(candidate_path))
    output = File.join(File.dirname(candidate_path), "visual-regions", stem)
    FileUtils.mkdir_p(output)
    out_dir = File.realpath(output)
  end

  manifest = JSON.parse(File.read(manifest_path))
  validate_manifest!(manifest)

  baseline_dimensions = image_dimensions(options[:magick], baseline_path)
  candidate_dimensions = image_dimensions(options[:magick], candidate_path)
  raise InputError, "baseline and candidate dimensions differ" unless baseline_dimensions == candidate_dimensions
  canvas_dimensions = [manifest.dig("canvas", "width"), manifest.dig("canvas", "height")]
  raise InputError, "screenshots do not match manifest canvas" unless baseline_dimensions == canvas_dimensions

  regions_root = File.join(out_dir, "regions")
  FileUtils.rm_rf(regions_root)
  FileUtils.mkdir_p(regions_root)
  comparator = File.expand_path("compare-screenshots.sh", __dir__)
  raise ToolError, "screenshot comparator is unavailable: #{comparator}" unless File.executable?(comparator)

  capture = manifest["capture"]
  thresholds = manifest["thresholds"]
  maximum_changed_ratio = 1.0 - thresholds["changed_similarity"].to_f
  rows = []
  region_reports = manifest["regions"].map do |region|
    id = region["id"]
    region_dir = File.join(regions_root, id)
    FileUtils.mkdir_p(region_dir)
    baseline_crop = File.join(region_dir, "baseline.png")
    candidate_crop = File.join(region_dir, "candidate.png")
    geometry = "#{region['width']}x#{region['height']}+#{region['x']}+#{region['y']}"
    run_capture(options[:magick], baseline_path, "-crop", geometry, "+repage", "-strip", baseline_crop)
    run_capture(options[:magick], candidate_path, "-crop", geometry, "+repage", "-strip", candidate_crop)

    if region["owner"] == "system"
      row = {
        "region_id" => id,
        "owner" => region["owner"],
        "kind" => region["kind"],
        "x" => region["x"],
        "y" => region["y"],
        "width" => region["width"],
        "height" => region["height"],
        "status" => "not_evaluated",
        "detail" => "system-owned region"
      }
      rows << row
      next region.merge(
        "evaluated" => false,
        "status" => "not_evaluated",
        "detail" => "system-owned region",
        "artifacts" => {
          "baseline" => relative_artifact(baseline_crop, out_dir),
          "candidate" => relative_artifact(candidate_crop, out_dir)
        }
      )
    end

    command = [
      comparator,
      "--magick", options[:magick],
      "--surface-id", capture["surface_id"],
      "--state", capture["state"],
      "--appearance", capture["appearance"],
      "--device", capture["device"],
      "--orientation", capture["orientation"],
      "--fixture", capture["fixture"],
      "--locale", capture["locale"],
      "--content-size", capture["content_size"],
      "--visual-ready", capture["visual_ready"],
      "--threshold", normalized_number(maximum_changed_ratio),
      "--min-ssim", normalized_number(thresholds["ssim"]),
      "--channel-delta", thresholds["channel_delta"].to_s,
      "--record-relative-to", out_dir,
      "--out", region_dir,
      baseline_crop,
      candidate_crop
    ]
    _stdout, stderr, comparator_status = run_capture(*command, accepted: [0, 1])
    raise ToolError, "region comparator rejected #{id}: #{stderr.strip}" if comparator_status == 2

    comparison = JSON.parse(File.read(File.join(region_dir, "summary.json"))).fetch("comparison")
    changed_similarity = comparison.fetch("changed_similarity").to_f
    ssim = comparison.fetch("ssim").to_f
    amplified = generate_amplified_artifacts(options[:magick], region_dir, thresholds["amplification"])
    edge = nil
    if region["kind"] == "action"
      edge = edge_coverage(
        options[:magick],
        baseline_crop,
        candidate_crop,
        region_dir,
        thresholds["edge_tolerance_pixels"],
        thresholds["amplification"]
      )
    end

    failures = []
    failures << "changed_similarity" if changed_similarity < thresholds["changed_similarity"].to_f
    failures << "ssim" if ssim < thresholds["ssim"].to_f
    if edge && edge["coverage"] < thresholds["action_edge_coverage"].to_f
      failures << "edge_coverage"
    end
    status = failures.empty? ? "passed" : "failed"
    detail = failures.empty? ? "all required metrics passed" : "below threshold: #{failures.join(', ')}"
    artifacts = {
      "baseline" => relative_artifact(baseline_crop, out_dir),
      "candidate" => relative_artifact(candidate_crop, out_dir),
      "comparison_summary" => relative_artifact(File.join(region_dir, "summary.json"), out_dir),
      "diff_heatmap" => relative_artifact(File.join(region_dir, "diff-heatmap.png"), out_dir),
      "overlay" => relative_artifact(File.join(region_dir, "overlay.png"), out_dir),
      "side_by_side" => relative_artifact(File.join(region_dir, "side-by-side.png"), out_dir),
      "diff_amplified" => relative_artifact(amplified["diff_amplified"], out_dir),
      "side_by_side_amplified" => relative_artifact(amplified["side_by_side_amplified"], out_dir)
    }
    artifacts["edge_coverage_amplified"] = relative_artifact(edge["artifact"], out_dir) if edge

    row = {
      "region_id" => id,
      "owner" => region["owner"],
      "kind" => region["kind"],
      "x" => region["x"],
      "y" => region["y"],
      "width" => region["width"],
      "height" => region["height"],
      "changed_similarity" => normalized_number(changed_similarity),
      "ssim" => normalized_number(ssim),
      "edge_coverage" => edge ? normalized_number(edge["coverage"]) : "",
      "status" => status,
      "detail" => detail
    }
    rows << row

    region.merge(
      "evaluated" => true,
      "changed_similarity" => changed_similarity,
      "ssim" => ssim,
      "edge_coverage" => edge && edge["coverage"],
      "edge_details" => edge && edge.reject { |key, _value| key == "artifact" },
      "status" => status,
      "detail" => detail,
      "artifacts" => artifacts
    )
  end

  failed = region_reports.any? { |region| region["owner"] == "app" && region["status"] != "passed" }
  report = {
    "schema_version" => SCHEMA_VERSION,
    "gate" => "timeline_named_regions",
    "status" => failed ? "failed" : "passed",
    "detail" => failed ? "one or more app-owned regions failed" : "every app-owned named region passed",
    "manifest" => {
      "path" => File.basename(manifest_path),
      "sha256" => Digest::SHA256.file(manifest_path).hexdigest,
      "surface" => manifest["surface"]
    },
    "canvas" => manifest["canvas"],
    "baseline" => {
      "path" => File.basename(baseline_path),
      "sha256" => Digest::SHA256.file(baseline_path).hexdigest
    },
    "candidate" => {
      "path" => File.basename(candidate_path),
      "sha256" => Digest::SHA256.file(candidate_path).hexdigest
    },
    "thresholds" => thresholds,
    "regions" => region_reports
  }
  write_report(out_dir, report, rows)
  warn report["detail"] if failed
  exit(failed ? 1 : 0)
rescue OptionParser::ParseError, Errno::ENOENT, JSON::ParserError, InputError, ToolError => error
  detail = error.message
  if out_dir
    write_report(
      out_dir,
      invalid_report(detail, manifest_path, baseline_path, candidate_path),
      [{
        "region_id" => "__validation__",
        "owner" => "",
        "kind" => "",
        "status" => "invalid",
        "detail" => detail
      }]
    )
  end
  warn "error: #{detail}"
  exit 2
end
