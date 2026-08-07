#!/usr/bin/env ruby

require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

repository_root = Pathname.new(File.expand_path("..", __dir__))
verifier = repository_root.join("scripts/verify-legacy-resource-boundary.rb")
manifest = repository_root.join("docs/legacy-resource-audit.json")

def run_verifier(verifier, root)
  Open3.capture3(RbConfig.ruby, verifier.to_s, "--repository-root", root.to_s)
end

def plist(fonts:, background: false, twitter: false)
  font_items = fonts.map { |name| "<string>#{name}</string>" }.join
  background_item = background ? "<key>UIBackgroundModes</key><array><string>remote-notification</string></array>" : ""
  twitter_item = twitter ? "<key>LSApplicationQueriesSchemes</key><array><string>twitter</string></array>" : ""
  <<~PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>UIAppFonts</key><array>#{font_items}</array>#{background_item}#{twitter_item}</dict></plist>
  PLIST
end

def entitlements(apns: false)
  apns_item = apns ? "<key>aps-environment</key><string>development</string>" : ""
  <<~PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>#{apns_item}</dict></plist>
  PLIST
end

Dir.mktmpdir("misscat-legacy-resource-") do |directory|
  root = Pathname.new(directory)
  %w[
    MissCat.xcodeproj
    MissCat/Resources/SettingsFixtures
    images/ScreenShot/Fixture
    docs
  ].each { |path| FileUtils.mkdir_p(root.join(path)) }

  fonts = [
    "Font Awesome 5 Free-Regular-400.otf",
    "Font Awesome 5 Free-Solid-900.otf"
  ]
  fonts.each { |name| File.binwrite(root.join("MissCat/Resources", name), "5.9.0") }
  fixtures = %w[reaction-fixture.gif reaction-fixture.apngdata reaction-fixture.svg reaction-fixture.invalid]
  fixtures.each { |name| File.write(root.join("MissCat/Resources/SettingsFixtures", name), "fixture") }
  11.times { |index| File.write(root.join("images/ScreenShot/Fixture/#{index}.png"), "fixture") }
  FileUtils.cp(manifest, root.join("docs/legacy-resource-audit.json"))
  File.write(root.join("MissCat/Info.plist"), plist(fonts: fonts))
  File.write(root.join("MissCat/MissCat.entitlements"), entitlements)
  File.write(
    root.join("MissCat.xcodeproj/project.pbxproj"),
    (fonts + fixtures).map { |name| "#{name} in Resources" }.join("\n")
  )

  system("/usr/bin/git", "-C", root.to_s, "init", "-q", exception: true)
  system("/usr/bin/git", "-C", root.to_s, "add", ".", exception: true)

  stdout, stderr, status = run_verifier(verifier, root)
  abort "valid fixture failed: #{stdout}#{stderr}" unless status.success?

  File.write(root.join("MissCat/MissCat.entitlements"), entitlements(apns: true))
  _, stderr, status = run_verifier(verifier, root)
  abort "APNs entitlement unexpectedly passed" if status.success?
  abort "APNs diagnostic absent" unless stderr.include?("retired APNs entitlement remains")
  File.write(root.join("MissCat/MissCat.entitlements"), entitlements)

  File.write(root.join("MissCat/Info.plist"), plist(fonts: fonts, background: true))
  _, stderr, status = run_verifier(verifier, root)
  abort "background mode unexpectedly passed" if status.success?
  abort "background mode diagnostic absent" unless stderr.include?("retired Info.plist capability remains")
  File.write(root.join("MissCat/Info.plist"), plist(fonts: fonts))

  brand = "MissCat/Resources/Font Awesome 5 Brands-Regular-400.otf"
  File.binwrite(root.join(brand), "5.9.0")
  system("/usr/bin/git", "-C", root.to_s, "add", brand, exception: true)
  _, stderr, status = run_verifier(verifier, root)
  abort "Brands font unexpectedly passed" if status.success?
  abort "Brands font diagnostic absent" unless stderr.include?("unused Brands font is still tracked")
end

puts "Legacy resource boundary verifier fixtures passed."
