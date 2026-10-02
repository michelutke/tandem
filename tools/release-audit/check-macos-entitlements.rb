#!/usr/bin/env ruby
# frozen_string_literal: true

# E22-04: App Sandbox entitlements check for the TandemApp Release build.
# E71-09: the entitlements of a target must equal that target's list in
# tools/release-audit/mac-entitlements.allowlist (set difference empty in both directions;
# `optional` entries may be absent). com.apple.security.cs.* and get-task-allow are never allowed.
#
# Usage:
#   ruby tools/release-audit/check-macos-entitlements.rb --entitlements PATH [--target app|share] [--allowlist PATH]
#
# The PATH should point to the target's .entitlements plist (or entitlements extracted with
# `codesign -d --entitlements - --xml` from the signed release artifact).

require 'rexml/document'
require 'optparse'

module MacOSEntitlementsCheck
  DEFAULT_ALLOWLIST = File.expand_path('mac-entitlements.allowlist', __dir__)

  FORBIDDEN_PATTERNS = [
    /com\.apple\.security\.cs\./,  # Code-signing exceptions (allow-jit, allow-unsigned-executable-memory, etc.)
    /get-task-allow/               # Debugger entitlement
  ].freeze

  def self.load_allowlist(path, target)
    required = []
    optional = []
    File.readlines(path).each_with_index do |raw_line, index|
      line = raw_line.strip
      next if line.empty? || line.start_with?('#')

      tokens = line.split(/\s+/)
      valid = [3, 4].include?(tokens.size) && tokens[2].match?(/\AE\d+-\d+\z/) &&
              (tokens.size == 3 || tokens[3] == 'optional')
      abort "Error: #{path}:#{index + 1}: expected `<target> <entitlement> <issue ID> [optional]`, got: #{line.inspect}" unless valid
      next unless tokens[0] == target

      (tokens.size == 4 ? optional : required) << tokens[1]
    end
    abort "Error: no allowlist entries for target #{target.inspect} in #{path}" if required.empty? && optional.empty?
    [required, optional]
  end

  def self.check(entitlements_path, target: 'app', allowlist_path: DEFAULT_ALLOWLIST)
    doc = REXML::Document.new(File.read(entitlements_path))
    dict = doc.root.elements['dict']

    unless dict
      warn "Error: No <dict> found in #{entitlements_path}"
      exit 1
    end

    parsed = parse_plist_dict(dict)
    required, optional = load_allowlist(allowlist_path, target)

    parsed.each_key do |key|
      FORBIDDEN_PATTERNS.each do |pattern|
        if key =~ pattern
          warn "Error: Forbidden entitlement pattern found: #{key}"
          exit 1
        end
      end
    end

    (required - parsed.keys).each { |key| warn "Error: Missing required entitlement: #{key}" }
    (parsed.keys - required - optional).each { |key| warn "Error: Found unexpected entitlement: #{key}" }
    exit 1 unless (required - parsed.keys).empty? && (parsed.keys - required - optional).empty?

    puts "✓ Entitlements check passed (#{target}): #{parsed.size} entitlements match the allowlist"
  end

  private

  def self.parse_plist_dict(dict)
    result = {}
    keys = dict.elements.select { |e| e.name == 'key' }

    keys.each do |key_elem|
      key_name = key_elem.text
      # Find the next element after the key (could be true, false, string, etc.)
      key_index = dict.elements.index(key_elem)
      next_elem = dict.elements[key_index + 1]

      if next_elem.name == 'true'
        result[key_name] = true
      elsif next_elem.name == 'false'
        result[key_name] = false
      elsif next_elem.name == 'string'
        result[key_name] = next_elem.text
      elsif next_elem.name == 'array'
        result[key_name] = next_elem.elements.map(&:text)
      else
        result[key_name] = next_elem.text
      end
    end

    result
  end
end

options = { target: 'app', allowlist: MacOSEntitlementsCheck::DEFAULT_ALLOWLIST }
OptionParser.new do |opts|
  opts.banner = 'Usage: check-macos-entitlements.rb --entitlements PATH [--target app|share] [--allowlist PATH]'

  opts.on('--entitlements PATH', 'Path to the target entitlements file') do |path|
    options[:entitlements] = path
  end
  opts.on('--target TARGET', 'Allowlist target: app (default) or share') { |target| options[:target] = target }
  opts.on('--allowlist PATH', 'Path to mac-entitlements.allowlist') { |path| options[:allowlist] = path }
end.parse!

unless options[:entitlements]
  warn 'Error: --entitlements PATH is required'
  exit 1
end

MacOSEntitlementsCheck.check(options[:entitlements], target: options[:target], allowlist_path: options[:allowlist])
