#!/usr/bin/env ruby
# frozen_string_literal: true

# E21-03: Local Network privacy Info.plist check for the TandemApp target.
# Verifies that Info.plist contains:
#   - NSLocalNetworkUsageDescription: a non-empty string
#   - NSBonjourServices: an array containing _tandem._tcp
#
# E71-09: also fails when the plist carries any ATS exception key (NSAllowsLocalNetworking,
# NSAllowsArbitraryLoads*, NSExceptionDomains) anywhere, including inside NSAppTransportSecurity.
#
# Usage:
#   ruby tools/release-audit/check-macos-info-plist.rb --info-plist PATH
#
# The PATH should point to the TandemApp Info.plist file.

require 'rexml/document'
require 'optparse'

module MacOSInfoPlistCheck
  REQUIRED_BONJOUR_SERVICE = '_tandem._tcp'
  REQUIRED_SERVICE_MENU_ITEM = 'Send to phone'
  REQUIRED_SERVICE_SEND_FILE_TYPE = 'public.item'
  FORBIDDEN_ATS_KEYS = %w[
    NSAllowsLocalNetworking
    NSAllowsArbitraryLoads
    NSAllowsArbitraryLoadsInWebContent
    NSAllowsArbitraryLoadsForMedia
    NSExceptionDomains
  ].freeze

  SHARE_MAX_FILE_COUNT_KEY = 'NSExtensionActivationSupportsFileWithMaxCount'
  SHARE_MAX_FILE_COUNT = 20

  def self.check_share(info_plist_path)
    doc = REXML::Document.new(File.read(info_plist_path))
    extension = dict_entries(doc.root.elements['dict'])['NSExtension']
    attributes = extension && dict_entries(extension)['NSExtensionAttributes']
    rule = attributes && dict_entries(attributes)['NSExtensionActivationRule']
    count = rule&.name == 'dict' ? dict_entries(rule)[SHARE_MAX_FILE_COUNT_KEY] : nil

    unless count&.name == 'integer' && count.text.to_i == SHARE_MAX_FILE_COUNT && rule.elements.to_a('key').size == 1
      warn "Error: NSExtensionActivationRule must be exactly #{SHARE_MAX_FILE_COUNT_KEY} = #{SHARE_MAX_FILE_COUNT}"
      exit 1
    end

    puts "✓ Share extension Info.plist check passed: activation rule accepts 1..#{SHARE_MAX_FILE_COUNT} files"
  end

  def self.check(info_plist_path)
    doc = REXML::Document.new(File.read(info_plist_path))
    dict = doc.root.elements['dict']

    unless dict
      warn "Error: No <dict> found in #{info_plist_path}"
      exit 1
    end

    parsed = parse_plist_dict(dict)

    forbidden = doc.get_elements('//key').map(&:text) & FORBIDDEN_ATS_KEYS
    unless forbidden.empty?
      warn "Error: Forbidden ATS exception key(s) in Info.plist: #{forbidden.join(', ')}"
      exit 1
    end

    description = parsed['NSLocalNetworkUsageDescription']
    unless description.is_a?(String) && !description.strip.empty?
      warn 'Error: Missing or empty NSLocalNetworkUsageDescription'
      exit 1
    end

    services = parsed['NSBonjourServices']
    unless services.is_a?(Array) && services.include?(REQUIRED_BONJOUR_SERVICE)
      warn "Error: NSBonjourServices missing #{REQUIRED_BONJOUR_SERVICE}"
      exit 1
    end

    unless send_to_phone_service?(dict)
      warn "Error: NSServices missing '#{REQUIRED_SERVICE_MENU_ITEM}' with NSSendFileTypes " \
           "#{REQUIRED_SERVICE_SEND_FILE_TYPE}"
      exit 1
    end

    puts "✓ Info.plist check passed: NSLocalNetworkUsageDescription and NSBonjourServices " \
         "(#{REQUIRED_BONJOUR_SERVICE}) present"
  end

  private

  def self.send_to_phone_service?(root_dict)
    services_key = root_dict.elements.to_a('key').find { |key| key.text == 'NSServices' }
    return false unless services_key

    services = services_key.next_element
    return false unless services&.name == 'array'

    services.elements.to_a('dict').any? do |service|
      entries = dict_entries(service)
      menu_item = entries['NSMenuItem']
      next false unless menu_item&.name == 'dict'

      dict_entries(menu_item)['default']&.text == REQUIRED_SERVICE_MENU_ITEM &&
        entries['NSSendFileTypes']&.elements&.map(&:text)&.include?(REQUIRED_SERVICE_SEND_FILE_TYPE)
    end
  end

  def self.dict_entries(dict)
    dict.elements.to_a('key').to_h { |key| [key.text, key.next_element] }
  end

  def self.parse_plist_dict(dict)
    result = {}
    keys = dict.elements.select { |e| e.name == 'key' }

    keys.each do |key_elem|
      key_name = key_elem.text
      key_index = dict.elements.index(key_elem)
      next_elem = dict.elements[key_index + 1]

      result[key_name] =
        if next_elem.name == 'true'
          true
        elsif next_elem.name == 'false'
          false
        elsif next_elem.name == 'string'
          next_elem.text
        elsif next_elem.name == 'array'
          next_elem.elements.map(&:text)
        else
          next_elem.text
        end
    end

    result
  end
end

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: check-macos-info-plist.rb --info-plist PATH'

  opts.on('--share', 'Check a Share extension Info.plist activation rule instead of the app plist') do
    options[:share] = true
  end

  opts.on('--info-plist PATH', 'Path to TandemApp Info.plist file') do |path|
    options[:info_plist] = path
  end
end.parse!

unless options[:info_plist]
  warn 'Error: --info-plist PATH is required'
  exit 1
end

options[:share] ? MacOSInfoPlistCheck.check_share(options[:info_plist]) : MacOSInfoPlistCheck.check(options[:info_plist])
