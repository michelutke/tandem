#!/usr/bin/env ruby
# frozen_string_literal: true

# Tests for tools/planning/manual_gates.rb. Each test runs the real script as a subprocess against
# an isolated fixture tree (tmpdir with its own tools/planning + docs/planning/backlog +
# docs/testing), so nothing here touches the repo's real backlog or docs/testing/manual-gates.md.
#
#   ruby tools/planning/manual_gates_test.rb

require 'minitest/autorun'
require 'fileutils'
require 'open3'
require 'tmpdir'

SCRIPT = File.join(__dir__, '..', 'manual_gates.rb')

BACKLOG_FIXTURE = <<~YAML
  phase: 0
  epics:
    - id: E00
      issues:
        - id: E00-23
          title: "[docs] Physical device matrix and manual-gate procedure"
          acceptance:
            - "Some acceptance line."
          tdd:
            - "ci: someOtherTest_condition_expectedResult"
            - "manual: exampleGate_condition_expectedResult"
YAML

class ManualGatesTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('manual-gates-test')
    FileUtils.mkdir_p(File.join(@root, 'tools/planning'))
    FileUtils.mkdir_p(File.join(@root, 'docs/planning/backlog'))
    FileUtils.mkdir_p(File.join(@root, 'docs/testing'))
    FileUtils.cp(SCRIPT, File.join(@root, 'tools/planning/manual_gates.rb'))
    write_backlog(BACKLOG_FIXTURE)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write_backlog(yaml)
    File.write(File.join(@root, 'docs/planning/backlog/phase-0.yaml'), yaml)
  end

  def manual_gates_doc
    File.read(File.join(@root, 'docs/testing/manual-gates.md'))
  end

  def run_script(*args)
    Open3.capture3('ruby', 'tools/planning/manual_gates.rb', *args, chdir: @root)
  end

  def test_manualGatesDoc_everyManualTddEntry_hasMatchingHeading
    _out, err, write_status = run_script('--write')
    assert write_status.success?, err

    doc = manual_gates_doc
    assert_includes doc, 'exampleGate_condition_expectedResult'
    assert_includes doc, 'E00-23'

    _check_out, check_err, check_status = run_script('--check')
    assert check_status.success?, check_err
  end

  def test_manualGatesDoc_headingWithoutBacklogEntry_checkFails
    _out, err, write_status = run_script('--write')
    assert write_status.success?, err

    # Drop the manual: entry from the backlog; its previously generated heading is now orphaned.
    write_backlog(BACKLOG_FIXTURE.sub(/\n\s*- "manual: exampleGate_condition_expectedResult"\n/, "\n"))

    check_out, check_err, check_status = run_script('--check')
    refute check_status.success?
    assert_match(/exampleGate_condition_expectedResult/, "#{check_out}#{check_err}")
  end
end
