#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/mitm-lab/test/nmap-phone-check_test.rb
#
# tdd (E15-12):
#   unit: nmapPhoneCheck_fixtureWithOpenPort_exitsOneListingPort
#   unit: nmapPhoneCheck_fixtureOnlyAllowlistedPorts_exitsZero
#   unit: nmapPhoneCheck_fixtureHostDown_exitsNonZero

require 'minitest/autorun'
require 'open3'

class NmapPhoneCheckTest < Minitest::Test
  SCRIPT = File.expand_path('../nmap-phone-check.sh', __dir__)
  FIXTURES = File.expand_path('fixtures/nmap', __dir__)

  def run_script(fixture_name)
    fixture_path = File.join(FIXTURES, "#{fixture_name}.xml")
    stdout, stderr, status = Open3.capture3(SCRIPT, '--test-fixture', fixture_path)
    [stdout, stderr, status.exitstatus]
  end

  def test_nmapPhoneCheck_fixtureWithOpenPort_exitsOneListingPort
    stdout, stderr, exitstatus = run_script('open-port')

    refute_equal 0, exitstatus, 'expected non-zero exit on open non-allowlisted port'
    output = stdout + stderr
    assert_includes output, '22', 'expected port 22 mentioned in output'
    assert_includes output, 'ERROR', 'expected error message'
  end

  def test_nmapPhoneCheck_fixtureOnlyAllowlistedPorts_exitsZero
    stdout, stderr, exitstatus = run_script('allowlisted-only')

    assert_equal 0, exitstatus, "expected zero exit on allowlisted ports only, got stderr: #{stderr}"
  end

  def test_nmapPhoneCheck_fixtureHostDown_exitsNonZero
    stdout, stderr, exitstatus = run_script('host-down')

    refute_equal 0, exitstatus, 'expected non-zero exit on host down'
    output = stdout + stderr
    assert_includes output, 'down', 'expected host-down error in output'
  end
end
