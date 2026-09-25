#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-26: fails if a built macOS Release binary contains the `UITestScenario` string — the
# DEBUG-only XCUITest scenario-seeding hook (macos/TandemApp/UITestScenario.swift) must not exist
# in Release (invariant 2). E00-30 generalizes this into a fuller Mach-O symbol scan against an
# allowlisted set of test-only types.
#
#   ruby tools/ci/check_release_binary_no_ui_test_scenario.rb <path-to-binary>

module ReleaseBinaryScenarioCheck
  FORBIDDEN_STRING = 'UITestScenario'

  module_function

  # Returns an array of human-readable error strings; empty means the check passes.
  def check(binary_path)
    return ["#{binary_path}: no such file"] unless File.file?(binary_path)

    contents = File.binread(binary_path)
    return ["#{binary_path}: contains forbidden string '#{FORBIDDEN_STRING}'"] if contents.include?(FORBIDDEN_STRING)

    []
  end
end

if $PROGRAM_NAME == __FILE__
  binary_path = ARGV[0] or abort 'usage: check_release_binary_no_ui_test_scenario.rb <path-to-binary>'
  errors = ReleaseBinaryScenarioCheck.check(binary_path)

  if errors.empty?
    puts 'release binary scenario-hook check: OK'
    exit 0
  else
    warn "release binary scenario-hook check: FAILED\n\n#{errors.map { |e| "  #{e}" }.join("\n")}"
    exit 1
  end
end
