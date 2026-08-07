#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"

root = File.expand_path("..", __dir__)
lock = File.read(File.join(root, "Podfile.lock"), encoding: "UTF-8")
source = File.read(
  File.join(root, "MissCat/SwiftUI/SettingsAccounts/MissCatLicenseCatalog.swift"),
  encoding: "UTF-8"
)
acknowledgements_path = File.join(root, "MissCat/Resources/ThirdPartyAcknowledgements.plist")
provenance_path = File.join(root, "config/third-party-acknowledgements.lock.json")

dependency_block = lock[/^DEPENDENCIES:\n(?<body>.*?)(?=^[A-Z][A-Z ]+:)/m, :body]
abort "Could not parse DEPENDENCIES from Podfile.lock" unless dependency_block

locked = dependency_block.lines.map do |line|
  declaration = line[/^  - ([^\s(]+)/, 1]
  next unless declaration

  product = declaration.split("/").first
  product == "Firebase" ? "Firebase" : product
end.compact.uniq.sort

constant = source[/static let dependencyNames = \[(?<body>.*?)\]/m, :body]
abort "Could not parse dependencyNames" unless constant
generated = constant.scan(/"([^"]+)"/).flatten.uniq.sort

unless locked == generated
  warn "License inventory is stale."
  warn "Missing: #{(locked - generated).join(", ")}"
  warn "Unexpected: #{(generated - locked).join(", ")}"
  exit 1
end

pods_block = lock[/^PODS:\n(?<body>.*?)(?=^DEPENDENCIES:)/m, :body]
abort "Could not parse PODS from Podfile.lock" unless pods_block
locked_versions = pods_block.lines.each_with_object({}) do |line, versions|
  match = line.match(/^  - ([^ (\/]+)(?:\/[^ ]+)? \(([^)]+)\)/)
  next unless match && locked.include?(match[1])

  versions[match[1]] ||= match[2]
end

provenance = JSON.parse(File.read(provenance_path, encoding: "UTF-8"))
abort "Unsupported acknowledgement provenance schema" unless provenance["schemaVersion"] == 1
pinned = provenance.fetch("dependencies").each_with_object({}) do |entry, result|
  name = entry.fetch("name")
  abort "Duplicate acknowledgement provenance for #{name}" if result.key?(name)
  abort "Invalid source URL for #{name}" unless entry.fetch("sourceURL").match?(%r{\Ahttps://})
  abort "Invalid acknowledgement digest for #{name}" unless entry.fetch("acknowledgementSHA256").match?(/\A[0-9a-f]{64}\z/)
  result[name] = entry
end

unless pinned.keys.sort == locked && locked.all? { |name| pinned[name]["version"] == locked_versions[name] }
  warn "Pinned acknowledgement provenance is stale against Podfile.lock."
  exit 1
end

acknowledgements_json = IO.popen(
  ["plutil", "-convert", "json", "-o", "-", acknowledgements_path],
  &:read
)
acknowledgements = JSON.parse(acknowledgements_json)
authoritative = acknowledgements.fetch("PreferenceSpecifiers").each_with_object({}) do |entry, result|
  title = entry["Title"]
  text = entry["FooterText"]
  result[title] = text if locked.include?(title) && text
end

unless authoritative.keys.sort == locked && authoritative.values.all? { |text| !text.empty? }
  warn "Bundled CocoaPods acknowledgement content is incomplete."
  warn "Missing: #{(locked - authoritative.keys).join(", ")}"
  exit 1
end

normalize = ->(text) { text.lines.map(&:rstrip).join("\n") }
catalog_matches_provenance = lambda do |catalog|
  catalog.keys.sort == locked && locked.all? do |name|
    Digest::SHA256.hexdigest(normalize.call(catalog.fetch(name))) == pinned.fetch(name).fetch("acknowledgementSHA256")
  end
end

unless catalog_matches_provenance.call(authoritative)
  warn "Bundled acknowledgement content does not match reviewed provenance digests."
  exit 1
end

# Negative self-tests ensure a future verifier regression cannot accept either a
# content mutation or an incomplete catalogue while still reporting success.
mutated = authoritative.dup
first_name = locked.first
mutated[first_name] = mutated.fetch(first_name) + " altered"
abort "Mutation negative test was accepted" if catalog_matches_provenance.call(mutated)

truncated = authoritative.dup
truncated.delete(first_name)
abort "Truncation negative test was accepted" if catalog_matches_provenance.call(truncated)

puts "License inventory, versions, sources, and reviewed acknowledgement digests match #{locked.count} dependencies; mutation/truncation negatives rejected."
