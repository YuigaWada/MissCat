#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

root = File.expand_path("..", __dir__)
lock = File.read(File.join(root, "Podfile.lock"), encoding: "UTF-8")
source = File.read(
  File.join(root, "MissCat/View/Settings/LicenseViewController.swift"),
  encoding: "UTF-8"
)
acknowledgements_path = File.join(root, "MissCat/Resources/ThirdPartyAcknowledgements.plist")

dependency_block = lock[/^DEPENDENCIES:\n(?<body>.*?)(?=^[A-Z][A-Z ]+:)/m, :body]
abort "Could not parse DEPENDENCIES from Podfile.lock" unless dependency_block

locked = dependency_block.lines.map do |line|
  declaration = line[/^  - ([^\s(]+)/, 1]
  next unless declaration

  product = declaration.split("/").first
  product == "Firebase" ? "Firebase" : product
end.compact.uniq.sort

constant = source[/static let podfileLockDependencyNames = \[(?<body>.*?)\n    \]/m, :body]
abort "Could not parse podfileLockDependencyNames" unless constant
generated = constant.scan(/"([^"]+)"/).flatten.uniq.sort

unless locked == generated
  warn "License inventory is stale."
  warn "Missing: #{(locked - generated).join(", ")}"
  warn "Unexpected: #{(generated - locked).join(", ")}"
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

puts "License inventory and bundled acknowledgement text match #{locked.count} Podfile.lock dependencies."
