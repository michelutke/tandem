#!/usr/bin/env ruby
# frozen_string_literal: true

# E22-04: App Sandbox entitlements check for the TandemApp Release build.
# Verifies that the Release app has exactly the required entitlements:
#   - com.apple.security.app-sandbox: true
#   - com.apple.security.network.server: true
#   - com.apple.security.network.client: true
# And no other entitlements (e.g., no code-signing exceptions, no get-task-allow).
#
# Usage:
#   ruby tools/release-audit/check-macos-entitlements.rb --entitlements PATH
#
# The PATH should point to the TandemApp.entitlements plist file.

require 'rexml/document'
require 'optparse'

module MacOSEntitlementsCheck
  REQUIRED_ENTITLEMENTS = {
    'com.apple.security.app-sandbox' => true,
    'com.apple.security.network.server' => true,
    'com.apple.security.network.client' => true
  }.freeze

  FORBIDDEN_PATTERNS = [
    /com\.apple\.security\.cs\./,  # Code-signing exceptions (allow-jit, allow-unsigned-executable-memory, etc.)
    /get-task-allow/               # Debugger entitlement
  ].freeze

  def self.check(entitlements_path)
    doc = REXML::Document.new(File.read(entitlements_path))
    dict = doc.root.elements['dict']

    unless dict
      warn "Error: No <dict> found in #{entitlements_path}"
      exit 1
    end

    # Parse the plist dict into a hash
    parsed = parse_plist_dict(dict)

    # Check required entitlements
    REQUIRED_ENTITLEMENTS.each do |key, expected_value|
      unless parsed.key?(key)
        warn "Error: Missing required entitlement: #{key}"
        exit 1
      end

      actual_value = parsed[key]
      unless actual_value == expected_value
        warn "Error: Entitlement #{key} has value #{actual_value.inspect}, expected #{expected_value.inspect}"
        exit 1
      end
    end

    # Check for forbidden entitlements
    parsed.each_key do |key|
      FORBIDDEN_PATTERNS.each do |pattern|
        if key =~ pattern
          warn "Error: Forbidden entitlement pattern found: #{key}"
          exit 1
        end
      end
    end

    # Check that only the required entitlements are present
    extra_keys = parsed.keys - REQUIRED_ENTITLEMENTS.keys
    if extra_keys.any?
      warn "Error: Found unexpected entitlements: #{extra_keys.join(', ')}"
      exit 1
    end

    puts "✓ Entitlements check passed: exactly #{REQUIRED_ENTITLEMENTS.size} required entitlements found"
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

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: check-macos-entitlements.rb --entitlements PATH'

  opts.on('--entitlements PATH', 'Path to TandemApp.entitlements file') do |path|
    options[:entitlements] = path
  end
end.parse!

unless options[:entitlements]
  warn 'Error: --entitlements PATH is required'
  exit 1
end

MacOSEntitlementsCheck.check(options[:entitlements])
