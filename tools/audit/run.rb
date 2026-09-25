#!/usr/bin/env ruby
# frozen_string_literal: true

# E15-18: security audit suite runner — one command, one report.
#
# Discovers audit steps by convention: every direct subdirectory of a "tools root" that contains
# an executable `audit-step.sh` is a discovered tool, named after the directory's basename
# (decisions.md D-39). Each step is invoked as `audit-step.sh --subset <ci|full>`; a step that
# prints a `MANUAL-GATE: <reference>` line is a device-only manual gate and is reported as
# "pending" (never "passed", never counted as a failure) rather than actually running anything.
#
#   ruby tools/audit/run.rb --subset ci|full
#   ruby tools/audit/run.rb --only <tool>
#   ruby tools/audit/run.rb --tools-root <dir> --report-dir <dir>
#
# Fan-in across every *expected* tool (proving nothing is missing) is a separate Phase 1 gate,
# E15-23 — this runner only reports on what it discovers.

require 'json'
require 'open3'

module AuditRunner
  Result = Struct.new(:tool, :status, :detail, keyword_init: true)

  MANUAL_GATE = /\AMANUAL-GATE:\s*(.+)\z/.freeze
  STEP_SCRIPT = 'audit-step.sh'

  module_function

  # Sorted list of tool names: direct subdirectories of tools_root containing an audit-step.sh.
  def discover(tools_root)
    Dir.children(tools_root).select do |name|
      File.exist?(File.join(tools_root, name, STEP_SCRIPT))
    end.sort
  end

  def run(tools_root:, subset:, only: nil)
    tools = discover(tools_root)

    if only
      raise ArgumentError, "unknown tool for --only: #{only.inspect} (discovered: #{tools.join(', ')})" unless tools.include?(only)

      tools = [only]
    elsif tools.empty?
      raise ArgumentError, "no tools discovered under #{tools_root} (no #{STEP_SCRIPT} found)"
    end

    results = tools.map { |tool| run_one(tools_root, tool, subset) }
    overall = results.any? { |r| r.status == 'failed' } ? 'FAIL' : 'PASS'

    { subset: subset, overall: overall, results: results.map { |r| r.to_h } }
  end

  def run_one(tools_root, tool, subset)
    script = File.join(tools_root, tool, STEP_SCRIPT)
    output, status = Open3.capture2e(script, '--subset', subset)

    manual_line = output.each_line.map(&:chomp).find { |line| MANUAL_GATE.match?(line) }
    if manual_line
      Result.new(tool: tool, status: 'pending', detail: MANUAL_GATE.match(manual_line)[1])
    elsif status.success?
      Result.new(tool: tool, status: 'passed', detail: '')
    else
      Result.new(tool: tool, status: 'failed', detail: output.strip)
    end
  end

  def write_reports(report_dir, subset:, overall:, results:)
    steps = results.map { |r| { tool: r[:tool], status: r[:status], detail: r[:detail] } }

    json_path = File.join(report_dir, 'report.json')
    File.write(json_path, JSON.pretty_generate({ subset: subset, overall: overall, steps: steps }))

    md_path = File.join(report_dir, 'report.md')
    File.write(md_path, markdown_report(subset, overall, steps))

    [json_path, md_path]
  end

  def markdown_report(subset, overall, steps)
    out = +"# Security audit report\n\n"
    out << "Subset: `#{subset}`  \nOverall: **#{overall}**\n\n"
    out << "| Tool | Status | Detail |\n|---|---|---|\n"
    steps.each do |s|
      detail = s[:detail].to_s.gsub("\n", ' ').gsub('|', '\\|')
      out << "| #{s[:tool]} | #{s[:status]} | #{detail} |\n"
    end
    out
  end
end

if $PROGRAM_NAME == __FILE__
  subset_idx = ARGV.index('--subset')
  subset = subset_idx ? ARGV[subset_idx + 1] : 'full'
  unless %w[ci full].include?(subset)
    warn "invalid --subset #{subset.inspect}: expected 'ci' or 'full'"
    exit 1
  end

  only_idx = ARGV.index('--only')
  only = only_idx ? ARGV[only_idx + 1] : nil

  tools_root_idx = ARGV.index('--tools-root')
  tools_root = tools_root_idx ? ARGV[tools_root_idx + 1] : File.expand_path('..', __dir__)

  report_dir_idx = ARGV.index('--report-dir')
  report_dir = report_dir_idx ? ARGV[report_dir_idx + 1] : __dir__

  begin
    report = AuditRunner.run(tools_root: tools_root, subset: subset, only: only)
  rescue ArgumentError => e
    warn e.message
    exit 1
  end

  puts AuditRunner.markdown_report(report[:subset], report[:overall], report[:results])
  AuditRunner.write_reports(report_dir, subset: report[:subset], overall: report[:overall], results: report[:results])

  exit(report[:overall] == 'PASS' ? 0 : 1)
end
