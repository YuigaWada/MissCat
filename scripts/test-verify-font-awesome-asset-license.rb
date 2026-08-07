#!/usr/bin/env ruby

require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

repository_root = Pathname.new(File.expand_path("..", __dir__))
verifier = repository_root.join("scripts/verify-font-awesome-asset-license.rb")
notice = repository_root.join("ThirdPartyNotices/Font-Awesome-Free-LICENSE.txt")

def run_verifier(verifier, root)
  Open3.capture3(RbConfig.ruby, verifier.to_s, "--repository-root", root.to_s)
end

Dir.mktmpdir("misscat-font-license-") do |directory|
  root = Pathname.new(directory)
  FileUtils.mkdir_p(root.join("MissCat.xcodeproj"))
  FileUtils.mkdir_p(root.join("MissCat/Resources"))
  FileUtils.mkdir_p(root.join("MissCat/SwiftUI"))
  FileUtils.mkdir_p(root.join("ThirdPartyNotices"))

  font_names = [
    "Font Awesome 5 Free-Regular-400.otf",
    "Font Awesome 5 Free-Solid-900.otf"
  ]
  font_names.each do |name|
    File.binwrite(root.join("MissCat/Resources", name), "fixture Font Awesome 5.9.0 #{name}")
  end
  FileUtils.cp(notice, root.join("ThirdPartyNotices/Font-Awesome-Free-LICENSE.txt"))
  File.write(
    root.join("MissCat/SwiftUI/FontUsers.swift"),
    <<~SWIFT
      import SwiftUI
      let regular = Text("r").font(.custom("FontAwesome5Free-Regular", size: 12))
      let solid = Text("s").font(.custom("FontAwesome5Free-Solid", size: 12))
    SWIFT
  )
  File.write(
    root.join("MissCat.xcodeproj/project.pbxproj"),
    font_names.map { |name| "#{name}\n#{name} in Resources" }.join("\n")
  )

  plist = lambda do |names|
    items = names.map { |name| "    <string>#{name}</string>" }.join("\n")
    <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict><key>UIAppFonts</key><array>
      #{items}
      </array></dict></plist>
    PLIST
  end
  File.write(root.join("MissCat/Info.plist"), plist.call(font_names))

  system("/usr/bin/git", "-C", root.to_s, "init", "-q", exception: true)
  system("/usr/bin/git", "-C", root.to_s, "add", ".", exception: true)

  stdout, stderr, status = run_verifier(verifier, root)
  abort "valid fixture failed: #{stdout}#{stderr}" unless status.success?

  FileUtils.rm(root.join("ThirdPartyNotices/Font-Awesome-Free-LICENSE.txt"))
  _, stderr, status = run_verifier(verifier, root)
  abort "missing notice unexpectedly passed" if status.success?
  abort "missing notice diagnostic absent" unless stderr.include?("license notice is missing")
  FileUtils.cp(notice, root.join("ThirdPartyNotices/Font-Awesome-Free-LICENSE.txt"))

  File.write(root.join("MissCat/Info.plist"), plist.call([font_names.first]))
  _, stderr, status = run_verifier(verifier, root)
  abort "missing UIAppFonts entry unexpectedly passed" if status.success?
  abort "UIAppFonts diagnostic absent" unless stderr.include?("UIAppFonts Font Awesome entries differ")

  brand = "Font Awesome 5 Brands-Regular-400.otf"
  File.binwrite(root.join("MissCat/Resources", brand), "fixture Font Awesome 5.9.0 #{brand}")
  system("/usr/bin/git", "-C", root.to_s, "add", "MissCat/Resources/#{brand}", exception: true)
  File.write(root.join("MissCat/Info.plist"), plist.call(font_names + [brand]))
  _, stderr, status = run_verifier(verifier, root)
  abort "unapproved extra font unexpectedly passed" if status.success?
  abort "tracked font diagnostic absent" unless stderr.include?("tracked Font Awesome fonts differ")
end

puts "Font Awesome asset license verifier fixtures passed."
