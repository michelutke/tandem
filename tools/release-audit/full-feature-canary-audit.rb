#!/usr/bin/env ruby
# frozen_string_literal: true

# E71-07: release-time full-feature canary audit. Run by the owner after one session exercising
# notifications, clipboard, files, SMS, contacts, calls and mirroring at once; aggregates the
# pcap-audit and log-audit results for that session into a single report.
#
#   ruby tools/release-audit/full-feature-canary-audit.rb --pcap session.pcapng --port 7623 \
#     --manifest canaries.txt --logcat logcat.txt --unified-log unified.log [--min-media-bytes N]
#
# The manifest holds one `kind=canary` line per E15-17 canary kind (`#` comments allowed). A kind
# missing from it fails the audit, so the run cannot silently stop covering a channel.

require 'optparse'
require 'json'
require 'open3'
require_relative 'audit_report'

module FullFeatureCanaryAudit
  REQUIRED_KINDS = %w[
    notification-text clipboard file-name file-content sms-body sms-address contact-name
    caller-number input-text sentinel-coordinates display-name pairing-secret media-ticket
  ].freeze
  PCAP_AUDIT = File.expand_path('../pcap-audit', __dir__)
  LOG_AUDIT = File.expand_path('../log-audit/log-audit.sh', __dir__)

  module_function

  def parse_manifest(text)
    text.each_line.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }.to_h do |line|
      kind, canary = line.split('=', 2)
      raise "malformed manifest line: #{line.inspect}" if kind.to_s.empty? || canary.to_s.empty?

      [kind, canary]
    end
  end

  def manifest_check(manifest)
    missing = REQUIRED_KINDS - manifest.keys
    return AuditReport.pass('canary manifest covers every kind', "#{manifest.size} kinds") if missing.empty?

    AuditReport.fail('canary manifest covers every kind', "missing kinds: #{missing.join(', ')}")
  end

  # `output` is the tool's stdout (a JSON object on its last line); a tool that crashed or printed
  # no JSON is a failure, never a pass.
  def tool_check(name, output, success)
    json = output.lines.map(&:strip).reverse.find { |l| l.start_with?('{') }
    return AuditReport.fail(name, "no JSON result (exit #{success ? 0 : 'non-zero'}): #{output.strip}") unless json

    result = JSON.parse(json)
    return AuditReport.pass(name, json) if success && result['result'] == 'pass'

    AuditReport.fail(name, json)
  rescue JSON::ParserError
    AuditReport.fail(name, "unparseable result: #{json}")
  end

  def log_check(kind, source, output, success)
    name = "log-audit #{source} #{kind}"
    success ? AuditReport.pass(name) : AuditReport.fail(name, output.strip)
  end

  def run_tool(*cmd)
    output, status = Open3.capture2e(*cmd)
    [output, status.success?]
  end

  def run(pcap:, port:, manifest:, logs:, min_media_bytes:)
    checks = [manifest_check(manifest)]
    checks << tool_check('only TLS 1.3 records on Tandem port',
                         *run_tool('python3', "#{PCAP_AUDIT}/tls13_assertion.py", pcap, '--port', port.to_s))
    checks << tool_check('media connection carried traffic',
                         *run_tool('python3', "#{PCAP_AUDIT}/media_volume.py", pcap, '--port', port.to_s,
                                   '--min-bytes', min_media_bytes.to_s))
    manifest.each do |kind, canary|
      checks << tool_check("pcap canary #{kind}",
                           *run_tool('python3', "#{PCAP_AUDIT}/canary_scan.py", pcap, '--canary', canary))
      logs.each do |source, flag, path|
        checks << log_check(kind, source, *run_tool(LOG_AUDIT, '--canary', canary, flag, path))
      end
    end
    checks
  end
end

if $PROGRAM_NAME == __FILE__
  options = { min_media_bytes: 1_000_000 }
  parser = OptionParser.new do |o|
    o.on('--pcap FILE') { |v| options[:pcap] = v }
    o.on('--port PORT', Integer) { |v| options[:port] = v }
    o.on('--manifest FILE') { |v| options[:manifest] = v }
    o.on('--logcat FILE') { |v| options[:logcat] = v }
    o.on('--unified-log FILE') { |v| options[:unified_log] = v }
    o.on('--min-media-bytes N', Integer) { |v| options[:min_media_bytes] = v }
  end
  parser.parse!(ARGV)

  required = %i[pcap port manifest logcat unified_log]
  missing = required.reject { |k| options[k] }
  abort "missing: #{missing.map { |k| "--#{k.to_s.tr('_', '-')}" }.join(', ')}" unless missing.empty?

  manifest = FullFeatureCanaryAudit.parse_manifest(File.read(options[:manifest]))
  logs = [['logcat', '--logcat', options[:logcat]], ['unified', '--unified-log', options[:unified_log]]]
  checks = FullFeatureCanaryAudit.run(pcap: options[:pcap], port: options[:port], manifest: manifest,
                                      logs: logs, min_media_bytes: options[:min_media_bytes])
  puts AuditReport.render('full-feature canary audit', checks)
  exit AuditReport.ok?(checks) ? 0 : 1
end
