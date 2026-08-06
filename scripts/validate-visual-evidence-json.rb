#!/usr/bin/ruby

require "json"

def fail_validation(message)
  warn "visual evidence JSON invalid: #{message}"
  exit 65
end

def exact_keys!(value, expected, label)
  fail_validation("#{label} must be an object") unless value.is_a?(Hash)
  actual = value.keys.sort
  wanted = expected.sort
  fail_validation("#{label} keys mismatch: #{actual.join(',')}") unless actual == wanted
end

def integer!(value, label, minimum: nil, maximum: nil)
  fail_validation("#{label} must be an integer") unless value.is_a?(Integer)
  fail_validation("#{label} is below range") if !minimum.nil? && value < minimum
  fail_validation("#{label} is above range") if !maximum.nil? && value > maximum
  value
end

def number!(value, label, minimum: nil, maximum: nil)
  fail_validation("#{label} must be a JSON number") unless value.is_a?(Numeric)
  numeric = value.to_f
  fail_validation("#{label} must be finite") unless numeric.finite?
  fail_validation("#{label} is below range") if !minimum.nil? && numeric < minimum
  fail_validation("#{label} is above range") if !maximum.nil? && numeric > maximum
  numeric
end

def string!(value, label, expected: nil)
  fail_validation("#{label} must be a non-empty string") unless value.is_a?(String) && !value.empty?
  fail_validation("#{label} metadata mismatch") if !expected.nil? && value != expected
  value
end

def boolean!(value, label, expected: nil)
  fail_validation("#{label} must be a boolean") unless value == true || value == false
  fail_validation("#{label} must be #{expected}") unless expected.nil? || value == expected
  value
end

def parse_json(path)
  JSON.parse(File.binread(path), create_additions: false)
rescue JSON::ParserError, Errno::ENOENT => error
  fail_validation("#{path}: #{error.message}")
end

mode = ARGV.shift

case mode
when "summary"
  if ARGV.length != 23
    fail_validation("summary validator expected 23 arguments, received #{ARGV.length}")
  end

  path, surface, state, appearance, device, orientation, fixture, locale, content_size, visual_ready,
    baseline_path, candidate_path, summary_path, heatmap_path, side_by_side_path, overlay_path,
    baseline_sha, candidate_sha, baseline_width, baseline_height, candidate_width, candidate_height,
    expected_schema = ARGV

  data = parse_json(path)
  exact_keys!(data, %w[artifacts baseline candidate capture comparison mask schema_version status], "root")
  integer!(data["schema_version"], "schema_version", minimum: expected_schema.to_i, maximum: expected_schema.to_i)
  string!(data["status"], "status", expected: "passed")

  capture = data["capture"]
  exact_keys!(capture, %w[appearance content_size device fixture locale orientation state surface_id visual_ready], "capture")
  {
    "surface_id" => surface,
    "state" => state,
    "appearance" => appearance,
    "device" => device,
    "orientation" => orientation,
    "fixture" => fixture,
    "locale" => locale,
    "content_size" => content_size,
    "visual_ready" => visual_ready
  }.each { |key, expected| string!(capture[key], "capture.#{key}", expected: expected) }

  [["baseline", baseline_path, baseline_sha, baseline_width, baseline_height],
   ["candidate", candidate_path, candidate_sha, candidate_width, candidate_height]].each do |label, expected_path, expected_sha, width, height|
    image = data[label]
    exact_keys!(image, %w[height path sha256 width], label)
    string!(image["path"], "#{label}.path", expected: expected_path)
    string!(image["sha256"], "#{label}.sha256", expected: expected_sha)
    integer!(image["width"], "#{label}.width", minimum: width.to_i, maximum: width.to_i)
    integer!(image["height"], "#{label}.height", minimum: height.to_i, maximum: height.to_i)
  end
  fail_validation("baseline and candidate dimensions differ") unless baseline_width == candidate_width && baseline_height == candidate_height

  comparison = data["comparison"]
  exact_keys!(comparison, %w[channel_delta changed_pixels changed_ratio changed_ratio_exceeded changed_similarity evaluated_pixels fuzz_percent max_changed_ratio max_normalized_rmse min_ssim normalized_rmse_exceeded rmse_absolute rmse_normalized ssim ssim_below_minimum], "comparison")
  fuzz = number!(comparison["fuzz_percent"], "comparison.fuzz_percent", minimum: 0, maximum: 100)
  channel_delta = integer!(comparison["channel_delta"], "comparison.channel_delta", minimum: 0, maximum: 8)
  changed_pixels = integer!(comparison["changed_pixels"], "comparison.changed_pixels", minimum: 0)
  evaluated_pixels = integer!(comparison["evaluated_pixels"], "comparison.evaluated_pixels", minimum: 1)
  total_pixels = baseline_width.to_i * baseline_height.to_i
  fail_validation("comparison.evaluated_pixels exceeds image area") if evaluated_pixels > total_pixels
  fail_validation("comparison.changed_pixels exceeds evaluated pixels") if changed_pixels > evaluated_pixels
  changed_ratio = number!(comparison["changed_ratio"], "comparison.changed_ratio", minimum: 0, maximum: 0.10)
  changed_similarity = number!(comparison["changed_similarity"], "comparison.changed_similarity", minimum: 0.90, maximum: 1)
  ssim = number!(comparison["ssim"], "comparison.ssim", minimum: 0.90, maximum: 1)
  number!(comparison["rmse_absolute"], "comparison.rmse_absolute", minimum: 0, maximum: 65_535)
  rmse_normalized = number!(comparison["rmse_normalized"], "comparison.rmse_normalized", minimum: 0, maximum: 1)
  max_changed_ratio = number!(comparison["max_changed_ratio"], "comparison.max_changed_ratio", minimum: 0, maximum: 0.10)
  min_ssim = number!(comparison["min_ssim"], "comparison.min_ssim", minimum: 0.90, maximum: 1)
  maximum_rmse = nil
  unless comparison["max_normalized_rmse"].nil?
    maximum_rmse = number!(comparison["max_normalized_rmse"], "comparison.max_normalized_rmse", minimum: 0, maximum: 1)
    fail_validation("comparison.rmse_normalized exceeds configured maximum") if rmse_normalized > maximum_rmse
  end
  boolean!(comparison["changed_ratio_exceeded"], "comparison.changed_ratio_exceeded", expected: false)
  boolean!(comparison["ssim_below_minimum"], "comparison.ssim_below_minimum", expected: false)
  boolean!(comparison["normalized_rmse_exceeded"], "comparison.normalized_rmse_exceeded", expected: false)
  expected_ratio = changed_pixels.to_f / evaluated_pixels
  fail_validation("comparison.changed_ratio is inconsistent") if (changed_ratio - expected_ratio).abs > 1e-9
  fail_validation("comparison.changed_similarity is inconsistent") if (changed_similarity - (1 - expected_ratio)).abs > 1e-9
  fail_validation("comparison gate is internally inconsistent") if changed_ratio > max_changed_ratio || ssim < min_ssim
  [fuzz, channel_delta] # Keep explicit validated values visible to static readers.

  artifacts = data["artifacts"]
  exact_keys!(artifacts, %w[heatmap overlay side_by_side summary], "artifacts")
  {
    "summary" => summary_path,
    "heatmap" => heatmap_path,
    "side_by_side" => side_by_side_path,
    "overlay" => overlay_path
  }.each { |key, expected| string!(artifacts[key], "artifacts.#{key}", expected: expected) }

  mask = data["mask"]
  exact_keys!(mask, %w[applied ignored_bounds ignored_pixels path requested sha256], "mask")
  requested = boolean!(mask["requested"], "mask.requested")
  applied = boolean!(mask["applied"], "mask.applied")
  ignored_pixels = integer!(mask["ignored_pixels"], "mask.ignored_pixels", minimum: 0, maximum: total_pixels - 1)
  if requested
    fail_validation("requested mask was not applied") unless applied
    mask_path = string!(mask["path"], "mask.path")
    mask_sha = string!(mask["sha256"], "mask.sha256")
    fail_validation("mask.sha256 must be lowercase SHA-256") unless mask_sha.match?(/\A[0-9a-f]{64}\z/)
    fail_validation("mask must ignore at least one pixel") if ignored_pixels.zero?
    bounds = mask["ignored_bounds"]
    exact_keys!(bounds, %w[height width x y], "mask.ignored_bounds")
    x = integer!(bounds["x"], "mask.ignored_bounds.x", minimum: 0)
    y = integer!(bounds["y"], "mask.ignored_bounds.y", minimum: 0)
    width = integer!(bounds["width"], "mask.ignored_bounds.width", minimum: 1)
    height = integer!(bounds["height"], "mask.ignored_bounds.height", minimum: 1)
    fail_validation("mask bounds exceed image dimensions") if x + width > baseline_width.to_i || y + height > baseline_height.to_i
    fail_validation("mask ignored pixels exceed its bounds") if ignored_pixels > width * height
    fail_validation("comparison.evaluated_pixels does not match mask") unless evaluated_pixels == total_pixels - ignored_pixels
    mask_fields = ["true", mask_path, mask_sha, ignored_pixels, x, y, width, height]
  else
    fail_validation("unrequested mask cannot be applied") if applied
    fail_validation("unrequested mask fields must be null") unless mask["path"].nil? && mask["sha256"].nil? && mask["ignored_bounds"].nil?
    fail_validation("unrequested mask ignored pixels must be zero") unless ignored_pixels.zero?
    fail_validation("unmasked comparison must evaluate every pixel") unless evaluated_pixels == total_pixels
    mask_fields = ["false", "none", "none", 0, 0, 0, 0, 0]
  end
  puts ["summary", fuzz, channel_delta, max_changed_ratio, min_ssim, maximum_rmse || "none", *mask_fields].join("\t")

when "recomputed"
  if ARGV.length != 2
    fail_validation("recomputed validator expected recorded and recomputed summaries")
  end
  recorded = parse_json(ARGV[0])
  recomputed = parse_json(ARGV[1])
  %w[schema_version status capture comparison].each do |key|
    fail_validation("recomputed #{key} mismatch") unless recorded[key] == recomputed[key]
  end
  %w[baseline candidate].each do |key|
    %w[sha256 width height].each do |field|
      fail_validation("recomputed #{key}.#{field} mismatch") unless recorded.dig(key, field) == recomputed.dig(key, field)
    end
  end
  %w[requested applied sha256 ignored_pixels ignored_bounds].each do |field|
    fail_validation("recomputed mask.#{field} mismatch") unless recorded.dig("mask", field) == recomputed.dig("mask", field)
  end

when "review"
  if ARGV.length != 12
    fail_validation("review validator expected 12 arguments, received #{ARGV.length}")
  end
  path, surface, state, appearance, device, fixture, locale, content_size, visual_ready,
    evidence_commit, overlay_sha, expected_schema = ARGV
  data = parse_json(path)
  exact_keys!(data, %w[case evidence_commit fixture overlay_sha256 reviewer schema_version visual_ready], "review root")
  integer!(data["schema_version"], "schema_version", minimum: expected_schema.to_i, maximum: expected_schema.to_i)
  exact_keys!(data["case"], %w[appearance content_size device locale state surface_id], "review case")
  {
    "surface_id" => surface,
    "state" => state,
    "appearance" => appearance,
    "device" => device,
    "locale" => locale,
    "content_size" => content_size
  }.each { |key, expected| string!(data["case"][key], "review.case.#{key}", expected: expected) }
  string!(data["fixture"], "review.fixture", expected: fixture)
  string!(data["visual_ready"], "review.visual_ready", expected: visual_ready)
  string!(data["evidence_commit"], "review.evidence_commit", expected: evidence_commit)
  string!(data["overlay_sha256"], "review.overlay_sha256", expected: overlay_sha)
  exact_keys!(data["reviewer"], %w[decision identity notes overlay_inspected_at_100_percent], "reviewer")
  string!(data["reviewer"]["decision"], "reviewer.decision", expected: "accepted")
  string!(data["reviewer"]["identity"], "reviewer.identity")
  string!(data["reviewer"]["notes"], "reviewer.notes")
  boolean!(data["reviewer"]["overlay_inspected_at_100_percent"], "reviewer.overlay_inspected_at_100_percent", expected: true)
else
  fail_validation("usage: validate-visual-evidence-json.rb summary|recomputed|review ...")
end
