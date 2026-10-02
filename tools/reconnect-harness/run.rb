#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/reconnect-harness/run.rb [--threshold 5.0] [--min-trials N] <log> [<log>...]
#
# Reports trials/p50/p95/max reconnect latency; exits 1 when p95 > threshold, any episode never
# reconnected, no episodes were found, or fewer than --min-trials were seen.

require 'optparse'
require_relative 'reconnect_harness'

threshold = ReconnectHarness::DEFAULT_THRESHOLD_SECONDS
min_trials = 1
parser = OptionParser.new do |o|
  o.on('--threshold SECONDS', Float) { |v| threshold = v }
  o.on('--min-trials N', Integer) { |v| min_trials = v }
end
paths = parser.parse(ARGV)
abort('usage: run.rb [--threshold S] [--min-trials N] <log>...') if paths.empty?

unreadable = paths.reject { |p| File.readable?(p) }
unless unreadable.empty?
  warn "unreadable: #{unreadable.join(', ')}"
  exit 1
end

latencies = paths.flat_map { |p| ReconnectHarness.latencies(File.read(p)) }
unrecovered = latencies.count(Float::INFINITY)
p50 = ReconnectHarness.percentile(latencies, 50)
p95 = ReconnectHarness.percentile(latencies, 95)
fmt = ->(v) { v.nil? ? 'n/a' : (v.infinite? ? 'inf' : format('%.3fs', v)) }

puts "trials=#{latencies.size} unrecovered=#{unrecovered} p50=#{fmt.call(p50)} " \
     "p95=#{fmt.call(p95)} max=#{fmt.call(latencies.max)} threshold=#{fmt.call(threshold)}"

failures = []
failures << 'no reconnect episodes found' if latencies.empty?
failures << "fewer than #{min_trials} trials" if latencies.size < min_trials
failures << "#{unrecovered} episode(s) never reconnected" if unrecovered.positive?
failures << 'p95 above threshold' if p95 && p95 > threshold
if failures.empty?
  puts 'PASS'
else
  puts "FAIL: #{failures.join('; ')}"
  exit 1
end
