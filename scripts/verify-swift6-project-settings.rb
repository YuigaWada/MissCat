#!/usr/bin/env ruby

require "json"
require "open3"
require "optparse"
require "pathname"
require "set"

DEFAULT_TARGETS = %w[
  MissCat
  MissCatShare
  MissCatTests
  MissCatUITests
  MissCatNoteUITests
  MissCatLoginProfileUITests
  MissCatShareKeychainUITests
].freeze

options = {
  project: Pathname.new(File.expand_path("../MissCat.xcodeproj/project.pbxproj", __dir__)),
  targets: DEFAULT_TARGETS
}
OptionParser.new do |parser|
  parser.on("--project PATH") { |value| options[:project] = Pathname.new(value).expand_path }
  parser.on("--required-targets LIST") { |value| options[:targets] = value.split(",").reject(&:empty?) }
end.parse!

output, error, status = Open3.capture3(
  "/usr/bin/plutil", "-convert", "json", "-o", "-", options.fetch(:project).to_s
)
unless status.success?
  warn "Swift 6 project setting verification failed: #{error.strip}"
  exit 2
end

objects = JSON.parse(output).fetch("objects")
targets = objects.values
  .select { |object| object["isa"] == "PBXNativeTarget" }
  .to_h { |object| [object.fetch("name"), object] }
errors = []
configuration_count = 0

options.fetch(:targets).each do |target_name|
  target = targets[target_name]
  unless target
    errors << "required native target is missing: #{target_name}"
    next
  end

  list_id = target["buildConfigurationList"]
  list = objects[list_id]
  unless list && list["isa"] == "XCConfigurationList"
    errors << "target has no valid configuration list: #{target_name}"
    next
  end

  configuration_ids = Array(list["buildConfigurations"])
  configuration_names = configuration_ids.map { |identifier| objects.dig(identifier, "name") }.compact
  errors << "target must have Debug and Release configurations: #{target_name}" unless configuration_names.to_set == %w[Debug Release].to_set

  configuration_ids.each do |identifier|
    configuration = objects[identifier]
    unless configuration && configuration["isa"] == "XCBuildConfiguration"
      errors << "target configuration is invalid: #{target_name}/#{identifier}"
      next
    end
    configuration_count += 1
    name = configuration.fetch("name", identifier)
    settings = configuration.fetch("buildSettings", {})
    label = "#{target_name}/#{name}"

    errors << "#{label} SWIFT_VERSION must be 6.0" unless settings["SWIFT_VERSION"].to_s == "6.0"
    unless settings["SWIFT_STRICT_CONCURRENCY"].to_s.downcase == "complete"
      errors << "#{label} SWIFT_STRICT_CONCURRENCY must be complete"
    end
    if settings["SWIFT_SUPPRESS_WARNINGS"].to_s.upcase == "YES"
      errors << "#{label} must not suppress Swift warnings"
    end
    flags = Array(settings["OTHER_SWIFT_FLAGS"]).join(" ")
    if flags.match?(/strict-concurrency=(?:minimal|targeted)|disable-actor-data-race-checks|suppress-warnings/i)
      errors << "#{label} contains a concurrency or warning suppression flag"
    end
  end
end

unless errors.empty?
  warn "Swift 6 project setting verification failed:"
  errors.each { |message| warn "- #{message}" }
  exit 1
end

puts "Swift 6 project settings verified: targets=#{options.fetch(:targets).length} configurations=#{configuration_count} language=6.0 strict=complete"
