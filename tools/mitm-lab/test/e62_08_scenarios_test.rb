#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/mitm-lab/test/e62_08_scenarios_test.rb
#
# E62-08 tdd (structure only; the scenarios need the real Mac app and a phone on adb):
#   ci: mitmLabE6208_scenarioFiles_parseAsExecutableClientScenariosAssertingNoInjection
#   ci: mitmLabE6208_uiTapPoint_findsNodeCentreByTextOrDescription
#   ci: e6208Integration_script_drivesRealMacInputWithoutSessionAndAuditsCanary

require 'minitest/autorun'
require 'open3'
require_relative '../runner'
require_relative '../e62-08-input-auth/lib/ui_tap_point'

class MitmLabE6208ScenariosTest < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  DIR = File.expand_path('../e62-08-input-auth/scenarios', __dir__)
  EXPECTED = {
    'mitmLab_inputWithNoActiveMirrorSession_notInjectedAndLogged' => 'closedWithCode(INPUT_DROPPED)',
    'mitmLab_inputWithStaleSessionReference_notInjectedAndLogged' => 'closedWithCode(INPUT_DROPPED)',
    'mitmLab_inputAfterMirrorStopped_notInjectedAndLogged' => 'closedWithCode(INPUT_DROPPED)',
    'mitmLab_inputFlood1000PerSecond_atMost240Injected' => 'closedWithCode(INPUT_RATE_LIMITED)',
    'mitmLab_inputOutOfRangeCoordinates_droppedNotClamped' => 'closedWithCode(INPUT_DROPPED)',
    'logAudit_droppedSetTextCanary_absentFromLogs' => 'closedWithCode(INPUT_DROPPED)'
  }.freeze

  def scenario_paths
    Dir.children(DIR).sort.map { |f| File.join(DIR, f) }
  end

  def test_mitmLabE6208_scenarioFiles_parseAsExecutableClientScenariosAssertingNoInjection
    paths = scenario_paths
    assert_equal EXPECTED.keys.sort, paths.map { |p| File.basename(p) }
    paths.each do |path|
      assert File.executable?(path), "#{path} not executable"
      meta = MitmLab.parse_metadata(path)
      assert_equal 'client', meta.role
      assert_equal File.basename(path), meta.name
      assert_equal EXPECTED.fetch(meta.name), meta.expect
      body = File.read(path)
      assert_includes body, 'e62-08-device.sh'
      assert_includes body, 'e62_08_send_input'
    end
  end

  def test_mitmLabE6208_scenarios_assertTheirDropReasonAndInjectionBound
    {
      'mitmLab_inputWithNoActiveMirrorSession_notInjectedAndLogged' => 'e62_08_assert_one_drop NoConsent TAP',
      'mitmLab_inputWithStaleSessionReference_notInjectedAndLogged' => 'e62_08_assert_one_drop SessionMismatch TAP',
      'mitmLab_inputOutOfRangeCoordinates_droppedNotClamped' => 'e62_08_assert_nothing_injected',
      'logAudit_droppedSetTextCanary_absentFromLogs' => 'e62_08_log_audit "$CANARY"'
    }.each do |name, assertion|
      assert_includes File.read(File.join(DIR, name)), assertion
    end
    flood = File.read(File.join(DIR, 'mitmLab_inputFlood1000PerSecond_atMost240Injected'))
    assert_includes flood, 'TAP 3000 1000'
    assert_includes flood, '-gt 240'
  end

  def test_mitmLabE6208_uiTapPoint_findsNodeCentreByTextOrDescription
    xml = <<~XML
      <hierarchy>
        <node index="0" text="Not now" content-desc="" bounds="[0,100][200,200]" />
        <node index="1" text="Start mirroring" content-desc="" bounds="[100,1000][500,1100]" />
        <node index="2" text="" content-desc="Start now" bounds="[10,20][30,60]" />
      </hierarchy>
    XML
    assert_equal [300, 1050], UiTapPoint.find(xml, 'start mirroring')
    assert_equal [20, 40], UiTapPoint.find(xml, 'Start now')
    assert_nil UiTapPoint.find(xml, 'Missing')
  end

  def test_e6208Integration_script_drivesRealMacInputWithoutSessionAndAuditsCanary
    script = File.join(ROOT, 'tools/harness/integration/e62-08.sh')
    assert File.executable?(script)
    body = File.read(script)
    assert_includes body, 'DISPATCHER_CALLS=0 DROPS=1'
    assert_includes body, 'e62_08_log_audit'
    _out, status = Open3.capture2e('bash', '-n', script)
    assert status.success?
  end
end
