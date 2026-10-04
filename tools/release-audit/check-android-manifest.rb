#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-28: platform-hardening baseline for the merged release manifest and its NSC / data
# extraction resources (invariants 1, 2, 4). Checks:
#   - <application> has allowBackup="false", fullBackupContent="false", a dataExtractionRules
#     reference, usesCleartextTraffic="false" and a networkSecurityConfig reference.
#   - the referenced dataExtractionRules resource excludes every domain (REQUIRED_EXCLUDED_DOMAINS
#     below)
#     from both <cloud-backup> and <device-transfer>: `domain="root"` alone is NOT everything —
#     Android's full-backup agent runs one traversal per domain token, each rooted at its own
#     directory (root/file/database/sharedpref/external, and their device_* transfer-only
#     counterparts), so root only prunes the root traversal.
#   - the networkSecurityConfig resource's <base-config> has cleartextTrafficPermitted="false",
#     no <trust-anchors><certificates src="user"/> anywhere, and no <debug-overrides>.
#   - every exported activity/activity-alias/service/receiver/provider is listed in
#     tools/release-audit/android-exported.allowlist with its guarding permission (or is missing
#     that permission despite being allowlisted for one).
#   - the declared <uses-permission> / <uses-permission-sdk-23> set equals
#     tools/release-audit/android-permissions.allowlist exactly (E71-09); each allowlist line
#     carries the issue ID that justifies the permission.
#   - no denied permission is declared via <uses-permission> or <uses-permission-sdk-23>, unless
#     it is present in tools/release-audit/android-denied-permissions.allowlist.
#
#   ruby tools/release-audit/check-android-manifest.rb --manifest PATH \
#     --data-extraction-rules PATH --nsc PATH \
#     [--allowlist PATH] [--denied-permissions-allowlist PATH] [--permissions-allowlist PATH]
#
# --manifest, --data-extraction-rules and --nsc are all mandatory: dataExtractionRules and NSC
# content can only be judged from the actual resource file (the manifest just carries an
# `@xml/...` reference), and omitting either one silently skipped that half of the check.
#
# Callers are responsible for producing the merged manifest and the *packaged* release resources
# (a real `:app:assembleRelease`, or fixture files for tests) — the packaged resources under
# build/intermediates/packaged_res/release/..., not the src/main (or src/release) source files
# directly, since a build-type-specific resource override wins resource merging and would
# otherwise go unchecked; this tool has no Android SDK/Gradle dependency of its own.

require 'rexml/document'
require 'optparse'
require 'set'

module AndroidManifestCheck
  class MalformedAllowlistError < StandardError; end

  DEFAULT_ALLOWLIST = File.expand_path('android-exported.allowlist', __dir__)
  DEFAULT_PERMISSIONS_ALLOWLIST = File.expand_path('android-permissions.allowlist', __dir__)
  DEFAULT_DENIED_PERMISSIONS_ALLOWLIST = File.expand_path('android-denied-permissions.allowlist', __dir__)

  # Every documented dataExtractionRules domain token (developer.android.com/identity/data/autobackup
  # XML config syntax): the non-device domains apply to both <cloud-backup> and <device-transfer>;
  # the device_* domains are the device-to-device-transfer-specific counterparts. All must be
  # excluded in both sections for "nothing leaves the device" to actually hold.
  REQUIRED_EXCLUDED_DOMAINS = %w[
    root file database sharedpref external
    device_root device_file device_database device_sharedpref
  ].freeze

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

  # Each non-comment, non-blank line must be exactly two whitespace-separated tokens: the
  # component name, and its required android:permission or "-" for none. A line with only a name
  # (the permission column forgotten) is a common way to silently allowlist a component with no
  # guard at all, so it is rejected rather than defaulted to "-". Trailing inline comments are not
  # supported: `name perm # why` is 4 tokens and fails closed rather than being misparsed.
  def load_allowlist(path)
    return {} unless File.exist?(path)

    allowlist = {}
    File.readlines(path).each_with_index do |raw_line, index|
      line = raw_line.strip
      next if line.empty? || line.start_with?('#')

      tokens = line.split(/\s+/)
      if tokens.size != 2
        raise MalformedAllowlistError,
              "#{path}:#{index + 1}: expected exactly 2 whitespace-separated tokens " \
              "(component name, permission or \"-\"), got #{tokens.size}: #{line.inspect}"
      end

      name, permission = tokens
      allowlist[name] = (permission == '-' ? nil : permission)
    end
    allowlist
  end

  # Each non-comment, non-blank line is exactly `<permission> <issue ID>`; a permission without
  # the justifying issue ID is rejected.
  def load_permissions_allowlist(path)
    return Set.new unless File.exist?(path)

    File.readlines(path).each_with_index.with_object(Set.new) do |(raw_line, index), set|
      line = raw_line.strip
      next if line.empty? || line.start_with?('#')

      tokens = line.split(/\s+/)
      unless tokens.size == 2 && tokens[1].match?(/\AE\d+-\d+\z/)
        raise MalformedAllowlistError,
              "#{path}:#{index + 1}: expected `<permission> <issue ID such as E20-02>`, got: #{line.inspect}"
      end

      set << tokens.first
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

  def check_manifest(doc, allowlist: {}, denied_permissions_allowlist: Set.new, permissions_allowlist: nil)
    violations = []
    application = doc.root.elements['application']
    if application.nil?
      violations << 'manifest has no <application> element'
      return violations
    end

    violations.concat(check_backup_attributes(application))
    violations.concat(check_denied_permissions(doc, denied_permissions_allowlist))
    violations.concat(check_declared_permissions(doc, permissions_allowlist)) unless permissions_allowlist.nil?
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

    uses_cleartext_traffic = application.attributes['android:usesCleartextTraffic']
    unless uses_cleartext_traffic == 'false'
      violations << "android:usesCleartextTraffic is #{uses_cleartext_traffic.inspect}, must be \"false\""
    end

    network_security_config = application.attributes['android:networkSecurityConfig']
    if network_security_config.nil? || network_security_config.empty?
      violations << 'android:networkSecurityConfig is missing from <application>'
    end
    violations
  end

  def check_denied_permissions(doc, denied_permissions_allowlist)
    violations = []
    %w[uses-permission uses-permission-sdk-23].each do |tag|
      doc.root.elements.each(tag) do |element|
        name = element.attributes['android:name']
        next unless DENIED_PERMISSIONS.include?(name)
        next if denied_permissions_allowlist.include?(name)

        violations << "denied permission #{name} is declared via <#{tag}> (not in android-denied-permissions.allowlist)"
      end
    end
    violations
  end

  def check_declared_permissions(doc, permissions_allowlist)
    declared = %w[uses-permission uses-permission-sdk-23].flat_map do |tag|
      doc.root.elements.to_a(tag).filter_map { |element| element.attributes['android:name'] }
    end.to_set

    unlisted = (declared - permissions_allowlist).sort.map do |name|
      "permission #{name} is declared but not in tools/release-audit/android-permissions.allowlist"
    end
    unused = (permissions_allowlist - declared).sort.map do |name|
      "permission #{name} is in tools/release-audit/android-permissions.allowlist but not declared"
    end
    unlisted + unused
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

      excluded_domains = section.elements.to_a('exclude').filter_map { |e| e.attributes['domain'] }.to_set
      missing_domains = REQUIRED_EXCLUDED_DOMAINS.reject { |domain| excluded_domains.include?(domain) }
      unless missing_domains.empty?
        violations << "<#{tag}> does not exclude domain(s) #{missing_domains.join(', ')} " \
                      "(domain=\"root\" alone does not exclude file/database/sharedpref/external)"
      end
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
    permissions_allowlist: AndroidManifestCheck::DEFAULT_PERMISSIONS_ALLOWLIST,
  }
  USAGE = 'usage: check-android-manifest.rb --manifest PATH --data-extraction-rules PATH --nsc PATH ' \
          '[--allowlist PATH] [--denied-permissions-allowlist PATH] [--permissions-allowlist PATH]'

  OptionParser.new do |opts|
    opts.banner = USAGE
    opts.on('--manifest PATH') { |v| options[:manifest] = v }
    opts.on('--data-extraction-rules PATH') { |v| options[:data_extraction_rules] = v }
    opts.on('--nsc PATH') { |v| options[:nsc] = v }
    opts.on('--allowlist PATH') { |v| options[:allowlist] = v }
    opts.on('--denied-permissions-allowlist PATH') { |v| options[:denied_permissions_allowlist] = v }
    opts.on('--permissions-allowlist PATH') { |v| options[:permissions_allowlist] = v }
  end.parse!(ARGV)

  if options[:manifest].nil? || options[:data_extraction_rules].nil? || options[:nsc].nil?
    warn USAGE
    exit 2
  end

  begin
    violations = []
    allowlist = AndroidManifestCheck.load_allowlist(options[:allowlist])
    denied_permissions_allowlist = AndroidManifestCheck.load_denied_permissions_allowlist(options[:denied_permissions_allowlist])
    violations.concat(
      AndroidManifestCheck.check_manifest(
        AndroidManifestCheck.read_xml(options[:manifest]),
        allowlist: allowlist,
        denied_permissions_allowlist: denied_permissions_allowlist,
        permissions_allowlist: AndroidManifestCheck.load_permissions_allowlist(options[:permissions_allowlist]),
      ),
    )
    violations.concat(AndroidManifestCheck.check_data_extraction_rules(AndroidManifestCheck.read_xml(options[:data_extraction_rules])))
    violations.concat(AndroidManifestCheck.check_network_security_config(AndroidManifestCheck.read_xml(options[:nsc])))
  rescue AndroidManifestCheck::MalformedAllowlistError => e
    warn "android manifest check: FAILED\n  #{e.message}"
    exit 1
  end

  if violations.empty?
    puts 'android manifest check: OK'
    exit 0
  else
    warn "android manifest check: FAILED\n#{violations.map { |v| "  #{v}" }.join("\n")}"
    exit 1
  end
end
