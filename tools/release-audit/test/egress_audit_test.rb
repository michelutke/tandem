# frozen_string_literal: true

# ruby tools/release-audit/test/egress_audit_test.rb
#
# E71-14 tdd:
#   unit: egressAuditParser_flowToThirdPartyHostFixture_exitsNonZero

require 'minitest/autorun'
require 'open3'
require_relative '../egress-audit'

class EgressAuditTest < Minitest::Test
  FIXTURES = File.expand_path('../fixtures/egress', __dir__)
  TOOL = File.expand_path('../egress-audit.rb', __dir__)

  def run_tool(*args)
    Open3.capture3('ruby', TOOL, *args)
  end

  def fixture(name)
    File.join(FIXTURES, name)
  end

  def test_egressAuditParser_flowToThirdPartyHostFixture_exitsNonZero
    _out, err, status = run_tool('flows', '--side', 'mac', '--peer', '192.168.1.50', '--port', '7623',
                                 fixture('mac-third-party-host.tsv'))

    refute_predicate status, :success?
    assert_includes err, '52.84.150.12:443'
  end

  def test_egressAuditParser_macCaptureOnlyPhoneTandemPortFlows_exitsZero
    out, _err, status = run_tool('flows', '--side', 'mac', '--peer', '192.168.1.50', '--port', '7623',
                                 fixture('mac-phone-only.tsv'))

    assert_predicate status, :success?
    assert_includes out, 'passed'
  end

  def test_egressAuditParser_udpToPhone_exitsNonZero
    _out, _err, status = run_tool('flows', '--side', 'mac', '--peer', '192.168.1.50', '--port', '7623',
                                  fixture('mac-udp-to-phone.tsv'))

    refute_predicate status, :success?
  end

  def test_egressAuditParser_phoneCaptureOnlyMacTandemPortFlows_exitsZero
    _out, _err, status = run_tool('flows', '--side', 'phone', '--peer', '192.168.1.20', '--port', '7623',
                                  fixture('phone-mac-only.tsv'))

    assert_predicate status, :success?
  end

  def test_egressAuditParser_phoneCaptureWithMdnsIpv6_exitsNonZero
    _out, err, status = run_tool('flows', '--side', 'phone', '--peer', '192.168.1.20', '--port', '7623',
                                 fixture('phone-ipv6-mdns.tsv'))

    refute_predicate status, :success?
    assert_includes err, 'fe80::2:5353'
  end

  def test_egressAuditParser_procNetOtherUidSocketsIgnored_exitsZero
    _out, _err, status = run_tool('proc-net', '--uid', '10123', '--peer', '10.0.2.2', '--port', '6970',
                                  fixture('proc-net-tcp-mac-only'))

    assert_predicate status, :success?
  end

  def test_egressAuditParser_procNetIpv4MappedIpv6Remote_decodesToPeer
    _out, _err, status = run_tool('proc-net', '--uid', '10123', '--peer', '10.0.2.2', '--port', '6970',
                                  fixture('proc-net-tcp6-mapped-mac'))

    assert_predicate status, :success?
  end

  def test_egressAuditParser_procNetThirdPartySocket_exitsNonZero
    _out, err, status = run_tool('proc-net', '--uid', '10123', '--peer', '10.0.2.2', '--port', '6970',
                                 fixture('proc-net-tcp-third-party'))

    refute_predicate status, :success?
    assert_includes err, '13.84.150.12:443'
  end

  def test_egressAuditParser_procNetListeningUdpSocket_exitsNonZero
    _out, err, status = run_tool('proc-net', '--uid', '10123', '--peer', '10.0.2.2', '--port', '6970',
                                 fixture('proc-net-udp-listening'))

    refute_predicate status, :success?
    assert_includes err, '0.0.0.0:0'
  end

  def test_egressAuditParser_missingArguments_exitsTwo
    _out, _err, status = run_tool('flows')

    assert_equal 2, status.exitstatus
  end
end
