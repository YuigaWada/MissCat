#!/usr/bin/env ruby

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "set"

VERSION = "5.9.0"
NOTICE_PATH = "ThirdPartyNotices/Font-Awesome-Free-LICENSE.txt"
NOTICE_SHA256 = "e779748dfe75e84f974df3c7bc07f842011a100159158b0f1f49b2f2a5a515cb"
FONT_PATHS = [
  "MissCat/Resources/Font Awesome 5 Free-Regular-400.otf",
  "MissCat/Resources/Font Awesome 5 Free-Solid-900.otf"
].freeze
FONT_FAMILIES = %w[
  FontAwesome5Free-Regular
  FontAwesome5Free-Solid
].freeze

options = {
  repository_root: Pathname.new(File.expand_path("..", __dir__)),
  project: "MissCat.xcodeproj/project.pbxproj",
  plist: "MissCat/Info.plist"
}

OptionParser.new do |parser|
  parser.on("--repository-root PATH") { |value| options[:repository_root] = Pathname.new(value).expand_path }
  parser.on("--project PATH") { |value| options[:project] = value }
  parser.on("--plist PATH") { |value| options[:plist] = value }
end.parse!

root = options.fetch(:repository_root)
errors = []

tracked_output, tracked_error, tracked_status = Open3.capture3(
  "/usr/bin/git", "-C", root.to_s, "ls-files", "-z"
)
unless tracked_status.success?
  warn "Font Awesome asset license verification failed: #{tracked_error.strip}"
  exit 2
end
tracked = tracked_output.split("\0").reject(&:empty?).to_set

project_path = root.join(options.fetch(:project))
plist_path = root.join(options.fetch(:plist))
project = File.read(project_path, encoding: "UTF-8")
plist_output, plist_error, plist_status = Open3.capture3(
  "/usr/bin/plutil", "-convert", "json", "-o", "-", plist_path.to_s
)
unless plist_status.success?
  warn "Font Awesome asset license verification failed: #{plist_error.strip}"
  exit 2
end
plist = JSON.parse(plist_output)

notice = root.join(NOTICE_PATH)
errors << "license notice is not tracked: #{NOTICE_PATH}" unless tracked.include?(NOTICE_PATH)
if notice.file?
  actual_hash = Digest::SHA256.file(notice).hexdigest
  errors << "license notice does not match official Font Awesome #{VERSION} LICENSE.txt" unless actual_hash == NOTICE_SHA256
else
  errors << "license notice is missing: #{NOTICE_PATH}"
end

expected_paths = FONT_PATHS.to_set
tracked_font_paths = tracked.grep(%r{\AMissCat/Resources/Font Awesome.*\.otf\z}).to_set
unless tracked_font_paths == expected_paths
  errors << "tracked Font Awesome fonts differ: expected=#{expected_paths.to_a.sort.inspect} actual=#{tracked_font_paths.to_a.sort.inspect}"
end

declared_font_names = Array(plist["UIAppFonts"]).grep(/\AFont Awesome.*\.otf\z/).to_set
expected_font_names = FONT_PATHS.map { |path| File.basename(path) }.to_set
unless declared_font_names == expected_font_names
  errors << "UIAppFonts Font Awesome entries differ: expected=#{expected_font_names.to_a.sort.inspect} actual=#{declared_font_names.to_a.sort.inspect}"
end

FONT_PATHS.each do |relative_path|
  absolute_path = root.join(relative_path)
  basename = File.basename(relative_path)
  errors << "font is not tracked: #{relative_path}" unless tracked.include?(relative_path)
  unless absolute_path.file?
    errors << "font is missing: #{relative_path}"
    next
  end
  errors << "font does not identify Font Awesome #{VERSION}: #{relative_path}" unless File.binread(absolute_path).include?(VERSION)
  errors << "PBX file reference is missing: #{basename}" unless project.include?(basename)
  errors << "PBX resource membership is missing: #{basename}" unless project.include?("#{basename} in Resources")
end

shipping_source = tracked
  .grep(%r{\AMissCat/.*\.swift\z})
  .map { |path| File.read(root.join(path), encoding: "UTF-8") }
  .join("\n")
FONT_FAMILIES.each do |family|
  prefix = ".custom(\"#{family}\""
  errors << "shipping source does not use retained font family: #{family}" unless shipping_source.include?(prefix)
end

unless errors.empty?
  warn "Font Awesome asset license verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "Font Awesome asset license verified: version=#{VERSION} fonts=#{FONT_PATHS.length} notice_sha256=#{NOTICE_SHA256}"
