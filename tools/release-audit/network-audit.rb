#!/usr/bin/env ruby
# frozen_string_literal: true

# E71-08: release-time network audit. Run by the owner against the release candidate with every
# feature active; aggregates nmap against the phone, every mitm-lab scenario directory in one
# pass, and the `openssl s_client -tls1_2` downgrade check against the Mac listener.
#
#   ruby tools/release-audit/network-audit.rb --phone-ip IP --mac-host HOST --mac-port PORT \
#     [--target-host HOST --target-port PORT] [--timeout SECONDS]

require 'optparse'
require 'open3'
require_relative 'audit_report'
require_relative '../mitm-lab/runner'

module NetworkAudit
  MITM_LAB = File.expand_path('../mitm-lab', __dir__)
  NMAP_CHECK = File.join(MITM_LAB, 'nmap-phone-check.sh')
  EXPECTED_DIRS = %w[
    e15-09-pairing-abuse e15-10-cert-abuse e15-11-version-scenarios e15-20-preauth-dos e20-20-auth-flood
    e21-06-discovery-hint e60-05-media-ticket e62-08-input-auth e70-09-rotation
  ].freeze

  module_function

  def scenario_dirs(root = MITM_LAB)
    Dir.children(root).sort.reject { |d| d == 'selftest' }
       .map { |d| File.join(root, d, 'scenarios') }.select { |d| Dir.exist?(d) }
  end

  def missing_dirs_check(dirs)
    missing = EXPECTED_DIRS - dirs.map { |d| File.basename(File.dirname(d)) }
    return AuditReport.pass('every expected mitm-lab directory present', "#{dirs.size} directories") if missing.empty?

    AuditReport.fail('every expected mitm-lab directory present', "missing: #{missing.join(', ')}")
  end

  def mitm_check(dir, report)
    name = "mitm-lab #{File.basename(File.dirname(dir))}"
    return AuditReport.fail(name, report.errors.join('; ')) unless report.errors.empty?
    return AuditReport.pass(name, "#{report.results.size} scenario(s)") if report.ok?

    AuditReport.fail(name, "unexpected: #{report.failing.map { |r| "#{r.name} (#{r.observed})" }.join(', ')}")
  end

  def nmap_check(output, success)
    name = 'nmap -p- phone: zero open ports'
    success ? AuditReport.pass(name) : AuditReport.fail(name, output.strip)
  end

  # s_client exits 0 even after a failed handshake, so judge by the negotiated protocol line.
  def tls12_check(output)
    name = 'openssl s_client -tls1_2 against Mac listener fails'
    return AuditReport.fail(name, 'handshake negotiated TLSv1.2') if output.match?(/Protocol\s*:\s*TLSv1\.2/)

    AuditReport.pass(name)
  end

  def run(phone_ip:, mac_host:, mac_port:, target_env:, timeout:)
    checks = []
    output, status = Open3.capture2e(NMAP_CHECK, '--ip', phone_ip)
    checks << nmap_check(output, status.success?)
    dirs = scenario_dirs
    checks << missing_dirs_check(dirs)
    dirs.each { |dir| checks << mitm_check(dir, MitmLab.run(dir: dir, target_env: target_env, default_timeout: timeout)) }
    output, = Open3.capture2e('openssl', 's_client', '-connect', "#{mac_host}:#{mac_port}", '-tls1_2', stdin_data: '')
    checks << tls12_check(output)
    checks
  end
end

if $PROGRAM_NAME == __FILE__
  options = { timeout: 300 }
  OptionParser.new do |o|
    o.on('--phone-ip IP') { |v| options[:phone_ip] = v }
    o.on('--mac-host HOST') { |v| options[:mac_host] = v }
    o.on('--mac-port PORT') { |v| options[:mac_port] = v }
    o.on('--target-host HOST') { |v| options[:target_host] = v }
    o.on('--target-port PORT') { |v| options[:target_port] = v }
    o.on('--timeout SECONDS', Integer) { |v| options[:timeout] = v }
  end.parse!(ARGV)

  missing = %i[phone_ip mac_host mac_port].reject { |k| options[k] }
  abort "missing: #{missing.map { |k| "--#{k.to_s.tr('_', '-')}" }.join(', ')}" unless missing.empty?

  target_env = {}
  target_env['MITM_TARGET_HOST'] = options[:target_host] if options[:target_host]
  target_env['MITM_TARGET_PORT'] = options[:target_port] if options[:target_port]
  checks = NetworkAudit.run(phone_ip: options[:phone_ip], mac_host: options[:mac_host], mac_port: options[:mac_port],
                            target_env: target_env, timeout: options[:timeout])
  puts AuditReport.render('network audit', checks)
  exit AuditReport.ok?(checks) ? 0 : 1
end
