#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path("..", __dir__)
lock = File.read(File.join(root, "Podfile.lock"), encoding: "UTF-8")
source = File.read(
  File.join(root, "MissCat/View/Settings/LicenseViewController.swift"),
  encoding: "UTF-8"
)

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

puts "License inventory matches #{locked.count} Podfile.lock dependencies."
