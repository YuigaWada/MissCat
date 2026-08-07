#!/usr/bin/env ruby

require "json"
require "open3"
require "optparse"
require "pathname"
require "set"

options = { repository_root: Pathname.new(File.expand_path("..", __dir__)) }
OptionParser.new do |parser|
  parser.on("--repository-root PATH") { |value| options[:repository_root] = Pathname.new(value).expand_path }
end.parse!

root = options.fetch(:repository_root)
errors = []

def plist(path)
  output, error, status = Open3.capture3("/usr/bin/plutil", "-convert", "json", "-o", "-", path.to_s)
  raise "#{path}: #{error.strip}" unless status.success?

  JSON.parse(output)
end

tracked_output, tracked_error, tracked_status = Open3.capture3(
  "/usr/bin/git", "-C", root.to_s, "ls-files", "-z"
)
unless tracked_status.success?
  warn "Legacy resource boundary verification failed: #{tracked_error.strip}"
  exit 2
end
tracked = tracked_output.split("\0").reject(&:empty?).to_set
project = File.read(root.join("MissCat.xcodeproj/project.pbxproj"), encoding: "UTF-8")
info = plist(root.join("MissCat/Info.plist"))
entitlements = plist(root.join("MissCat/MissCat.entitlements"))
manifest = JSON.parse(File.read(root.join("docs/legacy-resource-audit.json"), encoding: "UTF-8"))

errors << "unsupported resource audit manifest schema" unless manifest["schema_version"] == 1
manifest_paths = Array(manifest["removed_candidates"]).map { |entry| entry["path"] }.to_set
expected_manifest_paths = Set.new([
  "MissCat/Resources/Font Awesome 5 Brands-Regular-400.otf",
  "MissCat/Info.plist#BGTaskSchedulerPermittedIdentifiers",
  "MissCat/Info.plist#UIBackgroundModes",
  "MissCat/Info.plist#LSApplicationQueriesSchemes:twitter",
  "MissCat/MissCat.entitlements#aps-environment"
])
errors << "resource audit manifest candidate set differs" unless manifest_paths == expected_manifest_paths

brand_path = "MissCat/Resources/Font Awesome 5 Brands-Regular-400.otf"
brand_name = File.basename(brand_path)
errors << "unused Brands font is still tracked" if tracked.include?(brand_path)
errors << "unused Brands font still exists" if root.join(brand_path).exist?
errors << "unused Brands font remains in PBX project" if project.include?(brand_name)
errors << "unused Brands font remains in UIAppFonts" if Array(info["UIAppFonts"]).include?(brand_name)

%w[BGTaskSchedulerPermittedIdentifiers UIBackgroundModes].each do |key|
  errors << "retired Info.plist capability remains: #{key}" if info.key?(key)
end
if Array(info["LSApplicationQueriesSchemes"]).include?("twitter")
  errors << "unused twitter query scheme remains"
end
errors << "retired APNs entitlement remains" if entitlements.key?("aps-environment")

retained_fonts = [
  "MissCat/Resources/Font Awesome 5 Free-Regular-400.otf",
  "MissCat/Resources/Font Awesome 5 Free-Solid-900.otf"
]
retained_fonts.each do |path|
  name = File.basename(path)
  errors << "protected font is not tracked: #{path}" unless tracked.include?(path)
  errors << "protected font is missing from PBX resources: #{name}" unless project.include?("#{name} in Resources")
  errors << "protected font is missing from UIAppFonts: #{name}" unless Array(info["UIAppFonts"]).include?(name)
end

screenshots = tracked.grep(%r{\Aimages/ScreenShot/.*\.png\z})
errors << "protected legacy screenshot count changed: expected=11 actual=#{screenshots.length}" unless screenshots.length == 11

fixture_paths = tracked.grep(%r{\AMissCat/Resources/SettingsFixtures/}).sort
errors << "settings fixture resource count changed: expected=4 actual=#{fixture_paths.length}" unless fixture_paths.length == 4
fixture_paths.each do |path|
  name = File.basename(path)
  errors << "settings fixture is missing PBX resource membership: #{name}" unless project.include?("#{name} in Resources")
end

unless errors.empty?
  warn "Legacy resource boundary verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "Legacy resource boundary verified: removed=5 retained_fonts=2 protected_screenshots=11 settings_fixtures=4"
