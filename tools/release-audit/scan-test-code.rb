#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-30 (D-30): test-only code must provably never ship. This scans text produced from a release
# artifact (dexdump output, a merged Android manifest, `nm` output over a macOS Release Mach-O
# binary) for symbols on tools/release-audit/test-only-symbols.txt, and separately checks that a
# macOS .app bundle contains only the app binary and the share extension.
#
#   ruby tools/release-audit/scan-test-code.rb text FILE... [--denylist PATH]
#   ruby tools/release-audit/scan-test-code.rb bundle APP_BUNDLE_PATH
#
# Callers are responsible for producing FILE (e.g. `dexdump -d classes.dex > dump.txt`, or
# `nm TandemApp > syms.txt`); this tool has no Android SDK or Xcode dependency of its own.

require 'set'

module ReleaseAudit
  DEFAULT_DENYLIST = File.expand_path('test-only-symbols.txt', __dir__)

  # Mach-O magic numbers (32/64-bit, both byte orders) and the fat-binary magic.
  MACHO_MAGICS = [0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe, 0xcafebabe, 0xbebafeca].freeze

  module_function

  def load_denylist(path = DEFAULT_DENYLIST)
    File.readlines(path).map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
  end

  # A denylist entry with a `.` is also checked in its `/`-separated form, so one entry matches
  # both dexdump's `Ldev/tandem/...;` descriptors and dot-separated manifest/symbol text.
  def patterns_for(symbol)
    return [symbol] unless symbol.include?('.')

    [symbol, symbol.tr('.', '/')].uniq
  end

  # Returns the subset of denylist entries that occur anywhere in text.
  def text_matches(text, denylist)
    text = text.dup.force_encoding(Encoding::BINARY)
    denylist.select { |symbol| patterns_for(symbol).any? { |p| text.include?(p.b) } }
  end

  # Returns human-readable "<symbol> found in <path>" strings; empty means the scan passes.
  def scan_files(paths, denylist)
    paths.flat_map do |path|
      matches = text_matches(File.binread(path), denylist)
      matches.map { |symbol| "#{symbol} found in #{path}" }
    end
  end

  def macho?(path)
    bytes = File.binread(path, 4)
    return false if bytes.nil? || bytes.bytesize < 4

    MACHO_MAGICS.include?(bytes.unpack1('N'))
  rescue Errno::ENOENT, Errno::EACCES
    false
  end

  # Checks a macOS .app bundle against the D-30 allowlist: Contents/MacOS holds only the app
  # binary, Contents/PlugIns holds only appex bundles (each holding only their own binary), and no
  # .xctest bundle or other Mach-O binary exists anywhere else in the tree. Returns a list of
  # human-readable violations; empty means the bundle passes.
  def bundle_violations(app_path)
    violations = []
    allowed = Set.new

    macos_dir = File.join(app_path, 'Contents', 'MacOS')
    if Dir.exist?(macos_dir)
      entries = Dir.children(macos_dir).sort
      violations << "Contents/MacOS has #{entries.size} entries (expected 1): #{entries.join(', ')}" if entries.size != 1
      entries.each { |e| allowed << File.join(macos_dir, e) }
    else
      violations << 'Contents/MacOS is missing'
    end

    plugins_dir = File.join(app_path, 'Contents', 'PlugIns')
    if Dir.exist?(plugins_dir)
      Dir.children(plugins_dir).sort.each do |entry|
        plugin_path = File.join(plugins_dir, entry)
        unless entry.end_with?('.appex')
          violations << "Contents/PlugIns/#{entry} is not an .appex bundle"
          next
        end
        plugin_macos_dir = File.join(plugin_path, 'Contents', 'MacOS')
        if Dir.exist?(plugin_macos_dir)
          plugin_entries = Dir.children(plugin_macos_dir).sort
          if plugin_entries.size != 1
            violations << "#{entry}/Contents/MacOS has #{plugin_entries.size} entries (expected 1): #{plugin_entries.join(', ')}"
          end
          plugin_entries.each { |e| allowed << File.join(plugin_macos_dir, e) }
        else
          violations << "#{entry}/Contents/MacOS is missing"
        end
      end
    end

    Dir.glob(File.join(app_path, '**', '*'), File::FNM_DOTMATCH).each do |path|
      next unless File.file?(path)

      relative = path.delete_prefix("#{app_path}/")
      violations << "unexpected .xctest bundle: #{relative}" if relative.include?('.xctest')
      violations << "unexpected executable: #{relative}" if !allowed.include?(path) && macho?(path)
    end

    violations
  end

  def list(items) = items.map { |i| "  #{i}" }.join("\n")
end

if $PROGRAM_NAME == __FILE__
  command = ARGV.shift
  case command
  when 'text'
    denylist_path = ReleaseAudit::DEFAULT_DENYLIST
    if (i = ARGV.index('--denylist'))
      ARGV.delete_at(i)
      denylist_path = ARGV.delete_at(i)
    end
    files = ARGV
    if files.empty?
      warn 'usage: scan-test-code.rb text FILE... [--denylist PATH]'
      exit 2
    end
    matches = ReleaseAudit.scan_files(files, ReleaseAudit.load_denylist(denylist_path))
    if matches.empty?
      puts "release scan: OK (no test-only symbols in #{files.size} file(s))"
      exit 0
    else
      warn "release scan: FAILED\n#{ReleaseAudit.list(matches)}"
      exit 1
    end
  when 'bundle'
    app_path = ARGV.shift
    if app_path.nil?
      warn 'usage: scan-test-code.rb bundle APP_BUNDLE_PATH'
      exit 2
    end
    violations = ReleaseAudit.bundle_violations(File.expand_path(app_path))
    if violations.empty?
      puts 'release scan: OK (bundle contents match allowlist)'
      exit 0
    else
      warn "release scan: FAILED\n#{ReleaseAudit.list(violations)}"
      exit 1
    end
  else
    warn 'usage: scan-test-code.rb text FILE... [--denylist PATH] | bundle APP_BUNDLE_PATH'
    exit 2
  end
end
