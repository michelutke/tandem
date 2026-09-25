#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-28: platform-hardening baseline for the merged release manifest and its NSC / data
# extraction resources (invariants 1, 2, 4). Checks:
#   - <application> has allowBackup="false", fullBackupContent="false" and a
#     dataExtractionRules reference.
#   - the referenced dataExtractionRules resource excludes domain="root" (everything) from both
#     <cloud-backup> and <device-transfer>.
#   - the networkSecurityConfig resource's <base-config> has cleartextTrafficPermitted="false",
#     no <trust-anchors><certificates src="user"/> anywhere, and no <debug-overrides>.
#   - every exported activity/activity-alias/service/receiver/provider is listed in
#     tools/release-audit/android-exported.allowlist with its guarding permission (or is missing
#     that permission despite being allowlisted for one).
#   - no denied permission is declared, unless it is present in
#     tools/release-audit/android-denied-permissions.allowlist.
#
#   ruby tools/release-audit/check-android-manifest.rb --manifest PATH
#     [--data-extraction-rules PATH] [--nsc PATH]
#     [--allowlist PATH] [--denied-permissions-allowlist PATH]
#
# Callers are responsible for producing the merged manifest (a real `:app:assembleRelease`, or a
# fixture file for tests); this tool has no Android SDK/Gradle dependency of its own.

require 'rexml/document'
require 'optparse'
require 'set'

module AndroidManifestCheck
  DEFAULT_ALLOWLIST = File.expand_path('android-exported.allowlist', __dir__)
  DEFAULT_DENIED_PERMISSIONS_ALLOWLIST = File.expand_path('android-denied-permissions.allowlist', __dir__)

  # D-28 / E00-28 denied-permission list. READ_CALL_LOG may be lifted per component via
  # android-denied-permissions.allowlist once E52-02 justifies it; the rest are never allowed.
  DENIED_PERMISSIONS = %w[
    android.permission.QUERY_ALL_PACKAGES
    android.permission.SYSTEM_ALERT_WINDOW
    android.permission.USE_FULL_SCREEN_INTENT
    android.permission.READ_CALL_LOG
    android.permission.MANAGE_EXTERNAL_STORAGE
    android.permission.REQUEST_INSTALL_PACKAGES
    android.permission.WRITE_SETTINGS
    android.permission.READ_LOGS
    android.permission.BIND_DEVICE_ADMIN
  ].freeze

  COMPONENT_TAGS = %w[activity activity-alias service receiver provider].freeze
  # activity/service/receiver default to exported when they declare an intent-filter and no
  # explicit android:exported attribute is present (pre-API 31 behavior; AGP's manifest merger
  # requires an explicit value once an intent-filter is present at targetSdk 31+, but a fixture or
  # an older merged manifest may still omit it).
  IMPLICIT_EXPORT_TAGS = %w[activity activity-alias service receiver].freeze

  module_function

  def load_allowlist(path)
    return {} unless File.exist?(path)

    File.readlines(path).each_with_object({}) do |line, map|
      line = line.strip
      next if line.empty? || line.start_with?('#')

      name, permission = line.split(/\s+/, 2)
      map[name] = (permission == '-' ? nil : permission)
    end
  end

  def load_denied_permissions_allowlist(path)
    return Set.new unless File.exist?(path)

    File.readlines(path).each_with_object(Set.new) do |line, set|
      line = line.strip
      set << line unless line.empty? || line.start_with?('#')
    end
  end

  def read_xml(path)
    REXML::Document.new(File.read(path))
  end

  # --- <application> checks -------------------------------------------------------------------

  def check_manifest(doc, allowlist: {}, denied_permissions_allowlist: Set.new)
    violations = []
    application = doc.root.elements['application']
    if application.nil?
      violations << 'manifest has no <application> element'
      return violations
    end

    violations.concat(check_backup_attributes(application))
    violations.concat(check_denied_permissions(doc, denied_permissions_allowlist))
    violations.concat(check_exported_components(doc, application, allowlist))
    violations
  end

  def check_backup_attributes(application)
    violations = []
    allow_backup = application.attributes['android:allowBackup']
    violations << "android:allowBackup is #{allow_backup.inspect}, must be \"false\"" unless allow_backup == 'false'

    full_backup_content = application.attributes['android:fullBackupContent']
    unless full_backup_content == 'false'
      violations << "android:fullBackupContent is #{full_backup_content.inspect}, must be \"false\""
    end

    data_extraction_rules = application.attributes['android:dataExtractionRules']
    if data_extraction_rules.nil? || data_extraction_rules.empty?
      violations << 'android:dataExtractionRules is missing from <application>'
    end
    violations
  end

  def check_denied_permissions(doc, denied_permissions_allowlist)
    violations = []
    doc.root.elements.each('uses-permission') do |element|
      name = element.attributes['android:name']
      next unless DENIED_PERMISSIONS.include?(name)
      next if denied_permissions_allowlist.include?(name)

      violations << "denied permission #{name} is declared (not in android-denied-permissions.allowlist)"
    end
    violations
  end

  def check_exported_components(doc, application, allowlist)
    violations = []
    package = doc.root.attributes['package']
    COMPONENT_TAGS.each do |tag|
      application.elements.each(tag) do |element|
        next unless exported?(element, tag)

        name = resolve_component_name(element.attributes['android:name'], package)
        unless allowlist.key?(name)
          violations << "exported #{tag} #{name} is not in tools/release-audit/android-exported.allowlist"
          next
        end

        required_permission = allowlist[name]
        next if required_permission.nil?

        actual_permission = element.attributes['android:permission']
        if actual_permission != required_permission
          violations << "#{tag} #{name} is allowlisted for #{required_permission} but declares " \
                        "android:permission=#{actual_permission.inspect}"
        end
      end
    end
    violations
  end

  def exported?(element, tag)
    exported = element.attributes['android:exported']
    return exported == 'true' if !exported.nil? || !IMPLICIT_EXPORT_TAGS.include?(tag)

    !element.elements['intent-filter'].nil?
  end

  def resolve_component_name(name, package)
    return name if name.nil? || !name.start_with?('.')

    "#{package}#{name}"
  end

  # --- dataExtractionRules resource -----------------------------------------------------------

  def check_data_extraction_rules(doc)
    violations = []
    %w[cloud-backup device-transfer].each do |tag|
      section = doc.root.elements[tag]
      if section.nil?
        violations << "dataExtractionRules is missing <#{tag}>"
        next
      end

      excludes_everything = section.elements.to_a('exclude').any? { |e| e.attributes['domain'] == 'root' }
      violations << "<#{tag}> does not exclude domain=\"root\" (all app data)" unless excludes_everything
    end
    violations
  end

  # --- networkSecurityConfig resource ---------------------------------------------------------

  def check_network_security_config(doc)
    violations = []
    base_config = doc.root.elements['base-config']
    if base_config.nil?
      violations << 'networkSecurityConfig is missing <base-config>'
    else
      permitted = base_config.attributes['cleartextTrafficPermitted']
      unless permitted == 'false'
        violations << "base-config cleartextTrafficPermitted is #{permitted.inspect}, must be \"false\""
      end
    end

    doc.root.elements.each('.//trust-anchors/certificates') do |certificates|
      src = certificates.attributes['src']
      violations << "trust-anchors declares src=\"user\" (system anchors only)" if src == 'user'
    end

    violations << 'networkSecurityConfig has a <debug-overrides> element (not allowed in a release build)' if
      doc.root.elements['debug-overrides']

    violations
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    allowlist: AndroidManifestCheck::DEFAULT_ALLOWLIST,
    denied_permissions_allowlist: AndroidManifestCheck::DEFAULT_DENIED_PERMISSIONS_ALLOWLIST,
  }
  OptionParser.new do |opts|
    opts.banner = 'usage: check-android-manifest.rb --manifest PATH [--data-extraction-rules PATH] ' \
                  '[--nsc PATH] [--allowlist PATH] [--denied-permissions-allowlist PATH]'
    opts.on('--manifest PATH') { |v| options[:manifest] = v }
    opts.on('--data-extraction-rules PATH') { |v| options[:data_extraction_rules] = v }
    opts.on('--nsc PATH') { |v| options[:nsc] = v }
    opts.on('--allowlist PATH') { |v| options[:allowlist] = v }
    opts.on('--denied-permissions-allowlist PATH') { |v| options[:denied_permissions_allowlist] = v }
  end.parse!(ARGV)

  if options[:manifest].nil?
    warn 'usage: check-android-manifest.rb --manifest PATH [--data-extraction-rules PATH] [--nsc PATH]'
    exit 2
  end

  violations = []
  allowlist = AndroidManifestCheck.load_allowlist(options[:allowlist])
  denied_permissions_allowlist = AndroidManifestCheck.load_denied_permissions_allowlist(options[:denied_permissions_allowlist])
  violations.concat(
    AndroidManifestCheck.check_manifest(
      AndroidManifestCheck.read_xml(options[:manifest]),
      allowlist: allowlist,
      denied_permissions_allowlist: denied_permissions_allowlist,
    ),
  )
  violations.concat(AndroidManifestCheck.check_data_extraction_rules(AndroidManifestCheck.read_xml(options[:data_extraction_rules]))) if options[:data_extraction_rules]
  violations.concat(AndroidManifestCheck.check_network_security_config(AndroidManifestCheck.read_xml(options[:nsc]))) if options[:nsc]

  if violations.empty?
    puts 'android manifest check: OK'
    exit 0
  else
    warn "android manifest check: FAILED\n#{violations.map { |v| "  #{v}" }.join("\n")}"
    exit 1
  end
end
