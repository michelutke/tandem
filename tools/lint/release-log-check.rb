#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-27: release-log lint for macOS Swift sources (invariant 7) — the macOS half of E00-17.
#
#   ruby tools/lint/release-log-check.rb              # check macos/ sources
#   ruby tools/lint/release-log-check.rb <dir-or-file> # check another path
#
# Fails (returns non-empty errors) if an `os_log`/`NSLog`/`print` call, or an `os.Logger` method
# call (`.debug`/`.info`/`.notice`/`.error`/`.fault`/`.log`), references a symbol from the shared
# `tools/lint/sensitive-symbols.txt` (E00-17) outside `#if DEBUG` (nested `#if`/`#elseif`/`#else`/
# `#endif` handled; `#if !DEBUG` counts as release, since that branch runs in release builds). A
# redacted/length-only derivation of a sensitive symbol — `.count`, `.utf8.count`, or a call
# wrapped in a `redacted(...)`/`lengthOnly(...)` helper — is not flagged; this repo's convention
# is that either form documents "this is a length/redacted representation, not raw content".
#
# Separately (regardless of the sensitive-symbol list), a `Logger` string interpolation with
# `privacy: .public` on a non-literal value fails unless the value's source expression is listed
# in `tools/lint/public-log-allowlist.txt` (enum/category values only) — default privacy stays
# `.private`.
#
# This is a static, best-effort, symbol-name/text based check (mirrors the Android detekt
# `NoSensitiveReleaseLog` rule's symbol-matching semantics), not a runtime guarantee; the runtime
# guarantee comes from `tools/pcap-audit` canaries (E15) and `tools/log-audit` (E15-17).

module ReleaseLogCheck
  DEFAULT_SENSITIVE_SYMBOLS_PATH = File.join(__dir__, 'sensitive-symbols.txt')
  DEFAULT_PUBLIC_ALLOWLIST_PATH = File.join(__dir__, 'public-log-allowlist.txt')

  LOG_CALL = /\b(?:os_log|NSLog|print|[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\.(?:debug|info|notice|error|fault|log))\s*\(/.freeze
  SAFE_SUFFIX = /\A\.(?:count|utf8\.count)\b/.freeze
  SAFE_WRAPPER_SUFFIX = /\A\.(?:redacted|lengthOnly)\(\s*\)/.freeze
  SAFE_PREFIX = /(?:redacted|lengthOnly)\($/.freeze
  LITERAL_VALUE = /\A(?:"[^"]*"|-?\d+(?:\.\d+)?|true|false)\z/.freeze

  BUILD_OUTPUT_DIRS = %w[build .build].freeze

  module_function

  # Returns an array of "file:line: message" strings; empty means the check passes.
  def check(target, sensitive_symbols_path: DEFAULT_SENSITIVE_SYMBOLS_PATH, public_allowlist_path: DEFAULT_PUBLIC_ALLOWLIST_PATH)
    symbols = read_list(sensitive_symbols_path)
    allowlist = read_list(public_allowlist_path)
    files(target).sort.flat_map { |file| check_file(file, symbols, allowlist) }
  end

  def files(target)
    return [target] if File.file?(target)
    return [] unless File.directory?(target)

    # Build outputs (xcodebuild -derivedDataPath build/, SwiftPM .build/) hold third-party checkouts, not our sources.
    Dir.glob(File.join(target, '**', '*.swift')).select do |path|
      File.file?(path) && (path.delete_prefix(target).split('/') & BUILD_OUTPUT_DIRS).empty?
    end
  end

  def read_list(path)
    return [] unless File.file?(path)

    File.readlines(path).map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
  end

  def check_file(file, symbols, allowlist)
    lines = File.readlines(file, chomp: true)
    exempt = debug_exempt_flags(lines)
    errors = []

    scan_calls(lines).each do |call|
      next if exempt[call[:start_line] - 1]

      errors.concat(sensitive_symbol_errors(file, call, symbols))
      errors.concat(public_privacy_errors(file, call, allowlist))
    end

    errors
  end

  # One entry per source line: true if that line's #if/#elseif/#else branch is only reachable in
  # a DEBUG build. #if DEBUG (and an #elseif DEBUG branch) is debug-exempt; #if !DEBUG is not
  # (that branch runs in release); an unrelated condition (e.g. `#if os(macOS)`) is not
  # debug-exempt either. Nesting: a line is exempt if any enclosing frame is a DEBUG branch.
  # #else resolution assumes the immediately preceding #if/#elseif condition was a single
  # `DEBUG`/`!DEBUG` test (the common case); an #else after an unrelated condition stays release.
  def debug_exempt_flags(lines)
    stack = []
    lines.map do |line|
      case line.strip
      when /\A#if\s+!DEBUG\b/
        stack.push(debug: false, relates_to_debug: true)
      when /\A#if\s+DEBUG\b/
        stack.push(debug: true, relates_to_debug: true)
      when /\A#if\b/
        stack.push(debug: false, relates_to_debug: false)
      when /\A#elseif\s+!DEBUG\b/
        stack[-1] = { debug: false, relates_to_debug: true } unless stack.empty?
      when /\A#elseif\s+DEBUG\b/
        stack[-1] = { debug: true, relates_to_debug: true } unless stack.empty?
      when /\A#elseif\b/
        stack[-1] = { debug: false, relates_to_debug: false } unless stack.empty?
      when /\A#else\b/
        unless stack.empty?
          frame = stack[-1]
          stack[-1] = frame[:relates_to_debug] ? { debug: !frame[:debug], relates_to_debug: true } : frame
        end
      when /\A#endif\b/
        stack.pop
      end
      stack.any? { |frame| frame[:debug] }
    end
  end

  # Finds every recognized log call and captures its (possibly multi-line) argument text.
  def scan_calls(lines)
    calls = []
    i = 0
    while i < lines.length
      match = LOG_CALL.match(lines[i])
      if match
        text, end_line = capture_call_args(lines, i, match.end(0))
        calls << { text: text, start_line: i + 1, callee: match[0].sub(/\($/, '') }
        i = end_line + 1
      else
        i += 1
      end
    end
    calls
  end

  # Scans forward from just after a call's opening '(' (depth 1), tracking string literals so
  # parens inside them are not mistaken for call structure, until the matching ')' is found.
  def capture_call_args(lines, line_idx, col)
    depth = 1
    in_string = false
    escape = false
    text = +''
    i = line_idx

    while depth.positive?
      line = lines[i]
      if line.nil? || col >= line.length
        text << "\n"
        i += 1
        col = 0
        return [text, i - 1] if i >= lines.length

        next
      end

      ch = line[col]
      if in_string
        text << ch
        if escape
          escape = false
        elsif ch == '\\'
          escape = true
        elsif ch == '"'
          in_string = false
        end
      else
        case ch
        when '"'
          in_string = true
          text << ch
        when '('
          depth += 1
          text << ch
        when ')'
          depth -= 1
          text << ch if depth.positive?
        else
          text << ch
        end
      end
      col += 1
    end

    [text, i]
  end

  def sensitive_symbol_errors(file, call, symbols)
    symbols.each do |symbol|
      call[:text].scan(/\b#{Regexp.escape(symbol)}\b/) do
        m = Regexp.last_match
        before = call[:text][0...m.begin(0)]
        after = call[:text][m.end(0)..]
        next if before.rstrip.match?(SAFE_PREFIX) || after.match?(SAFE_SUFFIX) || after.match?(SAFE_WRAPPER_SUFFIX)

        line = call[:start_line] + before.count("\n")
        return ["#{file}:#{line}: `#{call[:callee]}` logs `#{symbol}`, which is listed in " \
                'tools/lint/sensitive-symbols.txt (invariant 7).']
      end
    end
    []
  end

  def public_privacy_errors(file, call, allowlist)
    errors = []
    each_interpolation(call[:text]) do |content, offset|
      next unless content.match?(/privacy\s*:\s*\.public\b/)

      value = content.split(/,\s*privacy\s*:/, 2).first.to_s.strip
      next if value.empty? || LITERAL_VALUE.match?(value) || allowlist.include?(value)

      line = call[:start_line] + call[:text][0...offset].count("\n")
      errors << "#{file}:#{line}: `#{call[:callee]}` logs `#{value}` with `privacy: .public`; add its " \
                'expression to tools/lint/public-log-allowlist.txt (enum/category values only) or drop ' \
                'to the default `.private` privacy.'
    end
    errors
  end

  # Yields (content, start_offset) for each `\(...)` string interpolation in text, honoring one
  # level of nested parens inside the interpolation (e.g. a function call as the logged value).
  def each_interpolation(text)
    in_string = false
    escape = false
    i = 0
    len = text.length

    while i < len
      ch = text[i]
      unless in_string
        in_string = true if ch == '"'
        i += 1
        next
      end

      if escape
        escape = false
        i += 1
      elsif ch == '\\' && text[i + 1] == '('
        depth = 1
        j = i + 2
        while j < len && depth.positive?
          case text[j]
          when '(' then depth += 1
          when ')' then depth -= 1
          end
          j += 1
        end
        yield text[(i + 2)...(j - 1)], i
        i = j
      elsif ch == '\\'
        escape = true
        i += 1
      elsif ch == '"'
        in_string = false
        i += 1
      else
        i += 1
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  repo_root = File.expand_path(File.join(__dir__, '..', '..'))
  target = ARGV[0] || File.join(repo_root, 'macos')
  errors = ReleaseLogCheck.check(target)

  if errors.empty?
    puts 'release log check: OK'
    exit 0
  else
    warn "release log check: FAILED\n\n#{errors.map { |e| "  #{e}" }.join("\n")}"
    exit 1
  end
end
