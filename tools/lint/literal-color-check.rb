#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-32: literal-colour lint for macOS Swift sources (ui-spec §3.1, §5.1 acceptance: "Text uses
# tokens only; no literal colours in feature code").
#
#   ruby tools/lint/literal-color-check.rb              # check macos/ sources
#   ruby tools/lint/literal-color-check.rb <dir-or-file> # check another path
#
# Fails (returns non-empty errors) if a line outside `Packages/TandemDesign/` constructs a
# `Color`/`NSColor` literal (`Color(red: ...)`, `NSColor(calibratedRed: ...)`, `Color(.sRGB, ...)`)
# or references a system palette colour (`Color.red`, `.foregroundStyle(.blue)`, ...). Feature
# code must use a `TandemColor` token instead; `TandemColor` itself is the one place a literal
# value may appear.

module LiteralColorCheck
  EXCLUDED_PATH = %r{/Packages/TandemDesign/}
  BUILD_OUTPUT_DIRS = %w[build .build].freeze
  COLOR_CONSTRUCTOR = /\b(?:Color|NSColor)\s*\(\s*(?:red|hue|white|calibratedRed|colorLiteralRed|\.sRGB)\b/
  PALETTE_MEMBER = /\b(?:Color|NSColor)\.(red|blue|green|yellow|orange|purple|pink|gray|grey|black|white|cyan|mint|indigo|teal|brown)\b/

  module_function

  # Returns an array of "file:line: message" strings; empty means the check passes.
  def check(target)
    files(target).sort.flat_map { |file| check_file(file) }
  end

  def files(target)
    return [target] if File.file?(target)
    return [] unless File.directory?(target)

    # Build outputs (xcodebuild -derivedDataPath build/, SwiftPM .build/) hold third-party checkouts, not our sources.
    Dir.glob(File.join(target, '**', '*.swift')).select do |file|
      File.file?(file) && !file.match?(EXCLUDED_PATH) && (file.delete_prefix(target).split('/') & BUILD_OUTPUT_DIRS).empty?
    end
  end

  def check_file(file)
    errors = []
    File.readlines(file, chomp: true).each_with_index do |line, index|
      next if line.strip.start_with?('//')

      lineno = index + 1
      errors << "#{file}:#{lineno}: constructs a literal Color/NSColor; use a TandemColor token instead (ui-spec §3.1)." if line.match?(COLOR_CONSTRUCTOR)

      if (match = PALETTE_MEMBER.match(line))
        errors << "#{file}:#{lineno}: uses system palette colour `#{match[0]}`; use a TandemColor token instead (ui-spec §3.1)."
      end
    end
    errors
  end
end

if $PROGRAM_NAME == __FILE__
  repo_root = File.expand_path(File.join(__dir__, '..', '..'))
  target = ARGV[0] || File.join(repo_root, 'macos')
  errors = LiteralColorCheck.check(target)

  if errors.empty?
    puts 'literal color check: OK'
    exit 0
  else
    warn "literal color check: FAILED\n\n#{errors.map { |e| "  #{e}" }.join("\n")}"
    exit 1
  end
end
