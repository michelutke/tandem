#!/usr/bin/env ruby
# frozen_string_literal: true

# E15-01/E15-02/E15-03: conformance runner -- runs the Android (Kotlin, E15-01) and macOS (Swift,
# E15-02) codec/crypto conformance suites against protocol/vectors, merges their per-vector JSON
# reports (each platform's own `ConformanceRunner` writes one to `tools/conformance/reports/`), and
# exits non-zero if either platform's command fails to run or any single vector fails.
#
#   bash tools/conformance/run.sh
#   ruby tools/conformance/run.rb --only android|macos
#
# Mirrors tools/audit/run.rb's shape (module_function + a thin CLI section), but there is no step
# discovery here: exactly two platforms, both required unless --only narrows to one.

require 'json'
require 'open3'
require 'fileutils'

module ConformanceRunner
  PlatformResult = Struct.new(:platform, :command_ok, :command_output, :records, keyword_init: true)

  module_function

  # The real commands: each platform's own conformance-runner test class writes its per-vector
  # report to `report_file` as a side effect of running (android/core/pairing's
  # ConformanceRunnerTest, macos/Packages/TandemProtocol's ConformanceRunnerTests).
  def default_platforms(repo_root)
    {
      'android' => {
        chdir: File.join(repo_root, 'android'),
        command: %w[
          ./gradlew :core:pairing:testDebugUnitTest --rerun --tests
          dev.tandem.core.pairing.conformance.ConformanceRunnerTest
        ],
        report_file: File.join(repo_root, 'tools', 'conformance', 'reports', 'android-report.json')
      },
      'macos' => {
        chdir: File.join(repo_root, 'macos', 'Packages', 'TandemProtocol'),
        command: %w[swift test --filter ConformanceRunnerTests],
        report_file: File.join(repo_root, 'tools', 'conformance', 'reports', 'macos-report.json')
      }
    }
  end

  def run(platforms:, report_dir:)
    results = platforms.map { |name, spec| run_one(name, spec) }
    records = results.flat_map { |r| r.records || [] }
    failing = records.select { |rec| rec['outcome'] == 'fail' }
    command_failures = results.reject(&:command_ok)

    overall = failing.empty? && command_failures.empty? ? 'PASS' : 'FAIL'

    {
      overall: overall,
      platforms: results.map { |r| { platform: r.platform, commandOk: r.command_ok, vectorCount: (r.records || []).size } },
      failing: failing.map { |rec| { platform: rec['platform'], vectorId: rec['vectorId'], category: rec['category'] } },
      records: records
    }
  end

  def run_one(name, spec)
    FileUtils.rm_f(spec[:report_file])
    output, status = Open3.capture2e(*spec[:command], chdir: spec[:chdir])
    records =
      if File.exist?(spec[:report_file])
        JSON.parse(File.read(spec[:report_file])).each { |rec| rec['platform'] = name }
      end
    PlatformResult.new(platform: name, command_ok: status.success?, command_output: output, records: records)
  end

  def write_report(report_dir, result)
    FileUtils.mkdir_p(report_dir)
    path = File.join(report_dir, 'report.json')
    File.write(path, JSON.pretty_generate(result))
    path
  end
end

if $PROGRAM_NAME == __FILE__
  repo_root = File.expand_path('../..', __dir__)

  only_idx = ARGV.index('--only')
  only = only_idx ? ARGV[only_idx + 1] : nil

  platforms = ConformanceRunner.default_platforms(repo_root)
  if only
    unless platforms.key?(only)
      warn "unknown platform for --only: #{only.inspect} (expected one of: #{platforms.keys.join(', ')})"
      exit 1
    end
    platforms = { only => platforms[only] }
  end

  report_dir = File.join(repo_root, 'tools', 'conformance', 'reports')
  result = ConformanceRunner.run(platforms: platforms, report_dir: report_dir)
  ConformanceRunner.write_report(report_dir, result)

  result[:failing].each { |f| puts "FAIL #{f[:platform]}:#{f[:vectorId]}" }
  result[:platforms].each do |p|
    status = p[:commandOk] ? 'ok' : 'FAILED'
    puts "#{p[:platform]}: command #{status}, #{p[:vectorCount]} vectors reported"
  end
  puts "overall: #{result[:overall]}"

  exit(result[:overall] == 'PASS' ? 0 : 1)
end
