#!/usr/bin/env ruby
# frozen_string_literal: true

# tools/mitm-lab/runner.rb — E15-08: scenario harness scaffolding + scripted-scenario runner.
#
#   ruby tools/mitm-lab/runner.rb SCENARIO_DIR [--target-host HOST] [--target-port PORT] [--timeout SECONDS]
#
# Scenario format (see README.md for the full description): each scenario is one executable file
# directly under SCENARIO_DIR (not recursive). Its leading `#`-comment header declares:
#   mitm-scenario-role: client|server
#   mitm-scenario-expect: handshakeRejected | noPairAccepted | closedWithCode(<CODE>)
#   mitm-scenario-timeout: <seconds>   (optional; default 30, PRD/E15-08 acceptance)
#   mitm-scenario-name: <name>         (optional; defaults to the file's basename)
#
# The runner executes it with MITM_TARGET_HOST / MITM_TARGET_PORT in its environment (when given
# via --target-host/--target-port), waits up to its timeout, and reads the *last* line of the
# form "OUTCOME: <value>" printed on its stdout as the observed outcome. A scenario passes only
# when observed == the declared expectation; a mismatch, a timeout, a crash, or "no OUTCOME line
# at all" are all failures. An empty (or all-non-executable) scenario directory is always an
# error, never a silent pass.

require 'optparse'

module MitmLab
  DEFAULT_TIMEOUT = 30
  ROLES = %w[client server].freeze
  EXPECT_PATTERN = /\A(handshakeRejected|noPairAccepted|closedWithCode\(.+\))\z/.freeze

  Metadata = Struct.new(:name, :role, :expect, :timeout, keyword_init: true)

  Result = Struct.new(:name, :role, :expected, :observed, :status, :duration_s, :detail, keyword_init: true) do
    def pass? = status == :pass
  end

  Report = Struct.new(:results, :errors, keyword_init: true) do
    def ok? = errors.empty? && results.all?(&:pass?)
    def failing = results.reject(&:pass?)
  end

  module_function

  # Every regular, executable file directly under `dir`, sorted for a deterministic run order.
  def discover(dir)
    return [] unless Dir.exist?(dir)

    Dir.children(dir).sort
       .map { |name| File.join(dir, name) }
       .select { |path| File.file?(path) && File.executable?(path) }
  end

  def parse_metadata(path)
    fields = {}
    File.foreach(path) do |line|
      break unless line.start_with?('#') || line.strip.empty?

      if (m = line.match(/^#\s*mitm-scenario-(\w+):\s*(.+?)\s*$/))
        fields[m[1]] = m[2]
      end
    end

    role = fields['role']
    expect = fields['expect']
    raise "#{path}: missing `mitm-scenario-role` header" unless role
    raise "#{path}: mitm-scenario-role must be #{ROLES.join(' or ')}, got #{role.inspect}" unless ROLES.include?(role)
    raise "#{path}: missing `mitm-scenario-expect` header" unless expect
    unless expect.match?(EXPECT_PATTERN)
      raise "#{path}: mitm-scenario-expect #{expect.inspect} is not handshakeRejected, noPairAccepted, or closedWithCode(<code>)"
    end

    Metadata.new(
      name: fields['name'] || File.basename(path, '.*'),
      role: role,
      expect: expect,
      timeout: fields['timeout'] ? Integer(fields['timeout']) : nil
    )
  end

  def parse_outcome(output)
    line = output.lines.map(&:strip).reverse.find { |l| l.start_with?('OUTCOME:') }
    line&.delete_prefix('OUTCOME:')&.strip
  end

  def kill_group(pid)
    Process.kill('TERM', -pid)
    sleep 0.2
    Process.kill('KILL', -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  # Runs `path`, killing its whole process group if it outlives `timeout`. Returns
  # [exit_status_or_nil, combined_stdout_and_stderr]; a nil status means it timed out.
  def run_with_timeout(path, env, timeout)
    read, write = IO.pipe
    pid = Process.spawn(env, [path, path], out: write, err: write, pgroup: true)
    write.close

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    status = nil
    loop do
      _pid, status = Process.wait2(pid, Process::WNOHANG)
      break if status
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        kill_group(pid)
        Process.wait(pid)
        break
      end
      sleep 0.02
    end

    output = read.read
    read.close
    [status, output]
  end

  def run_one(path, target_env, default_timeout)
    meta = parse_metadata(path)
    env = target_env.transform_keys(&:to_s).transform_values(&:to_s)
    timeout = meta.timeout || default_timeout

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, output = run_with_timeout(path, env, timeout)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    if status.nil?
      Result.new(name: meta.name, role: meta.role, expected: meta.expect, observed: 'timeout', status: :fail,
                 duration_s: duration, detail: "exceeded #{timeout}s timeout")
    else
      observed = parse_outcome(output) || "no-outcome(exit=#{status.exitstatus})"
      detail = output.lines.last(5).join
      Result.new(name: meta.name, role: meta.role, expected: meta.expect, observed: observed,
                 status: (observed == meta.expect ? :pass : :fail), duration_s: duration, detail: detail)
    end
  rescue StandardError => e
    Result.new(name: File.basename(path), role: nil, expected: nil, observed: nil, status: :fail,
               duration_s: 0.0, detail: e.message)
  end

  def run(dir:, target_env: {}, default_timeout: DEFAULT_TIMEOUT)
    paths = discover(dir)
    return Report.new(results: [], errors: ["no scenario files found under #{dir}"]) if paths.empty?

    results = paths.map { |path| run_one(path, target_env, default_timeout) }
    Report.new(results: results, errors: [])
  end
end

if $PROGRAM_NAME == __FILE__
  options = { timeout: MitmLab::DEFAULT_TIMEOUT }
  parser = OptionParser.new do |o|
    o.banner = 'Usage: runner.rb SCENARIO_DIR [--target-host HOST] [--target-port PORT] [--timeout SECONDS]'
    o.on('--target-host HOST', 'Host the scenario should attack (passed as MITM_TARGET_HOST)') { |v| options[:target_host] = v }
    o.on('--target-port PORT', 'Port the scenario should attack (passed as MITM_TARGET_PORT)') { |v| options[:target_port] = v }
    o.on('--timeout SECONDS', Integer, "Default per-scenario timeout (default #{MitmLab::DEFAULT_TIMEOUT})") { |v| options[:timeout] = v }
  end
  parser.parse!(ARGV)

  dir = ARGV.shift
  if dir.nil?
    warn parser.banner
    exit 1
  end

  target_env = {}
  target_env['MITM_TARGET_HOST'] = options[:target_host] if options[:target_host]
  target_env['MITM_TARGET_PORT'] = options[:target_port] if options[:target_port]

  report = MitmLab.run(dir: dir, target_env: target_env, default_timeout: options[:timeout])

  report.results.each do |r|
    status = r.pass? ? 'PASS' : 'FAIL'
    puts format('%-4s %-40s role=%-6s expect=%-28s observed=%-28s (%.1fs)', status, r.name, r.role.to_s,
                r.expected.to_s, r.observed.to_s, r.duration_s)
    puts "     #{r.detail}" unless r.pass? || r.detail.to_s.empty?
  end
  report.errors.each { |e| warn "ERROR: #{e}" }

  if report.ok?
    puts "mitm-lab: #{report.results.size} scenario(s) passed"
  else
    names = report.failing.map(&:name)
    warn "mitm-lab: FAILED#{" (#{names.join(', ')})" unless names.empty?}"
    exit 1
  end
end
