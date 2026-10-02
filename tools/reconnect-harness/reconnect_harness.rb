# frozen_string_literal: true

require 'time'

# E20-12: reconnect latency (disconnect/dead event -> session Ready) from timestamped marker lines.
module ReconnectHarness
  MARKER = /TandemReconnect:?\s+event=(disconnected|dead|ready)\b/.freeze
  LOGCAT_TS = /\A(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\.(\d{3})/.freeze
  UNIFIED_TS = /\A(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+[+-]\d{4})/.freeze
  LOGCAT_TAG_PREFIX = /\A\S+ \S+\s+\d+\s+\d+ [A-Z] (?!TandemReconnect)\S+:/.freeze
  DEFAULT_THRESHOLD_SECONDS = 5.0

  module_function

  def timestamp(line)
    if (m = line.match(UNIFIED_TS))
      Time.strptime(m[1], '%Y-%m-%d %H:%M:%S.%N%z').to_r
    elsif (m = line.match(LOGCAT_TS))
      mon, day, hh, mm, ss, ms = m.captures.map(&:to_i)
      Time.utc(2000, mon, day, hh, mm, ss, ms * 1000).to_r
    end
  end

  def events(text)
    text.each_line.filter_map do |line|
      next if line.match?(LOGCAT_TAG_PREFIX)

      marker = line.match(MARKER)
      stamp = timestamp(line)
      [stamp, marker[1]] if marker && stamp
    end
  end

  # One latency (seconds) per episode; an episode that never reaches ready is Float::INFINITY.
  def latencies(text)
    open_at = nil
    result = []
    events(text).each do |stamp, kind|
      if kind == 'ready'
        next unless open_at

        result << (stamp - open_at).to_f
        open_at = nil
      else
        open_at ||= stamp
      end
    end
    result << Float::INFINITY if open_at
    result
  end

  def percentile(values, pct)
    return nil if values.empty?

    sorted = values.sort
    sorted[(pct / 100.0 * sorted.size).ceil - 1]
  end
end
