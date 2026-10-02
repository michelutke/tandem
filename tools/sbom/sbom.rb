#!/usr/bin/env ruby
# frozen_string_literal: true

# E71-10: CycloneDX SBOM + vulnerability scan for the Gradle and SwiftPM dependency trees.
#
#   ruby tools/sbom/sbom.rb generate            # rewrite tools/sbom/sbom.cdx.json
#   ruby tools/sbom/sbom.rb check               # fail if the committed SBOM is stale or a license is not allowed
#   ruby tools/sbom/sbom.rb scan [--advisories FILE]
#                                               # fail on unwaived high/critical findings; queries
#                                               # api.osv.dev (no credentials) unless --advisories is given
#
# Components come from android/gradle/verification-metadata.xml and every macos/Packages/*/Package.resolved.
# Licenses come from tools/sbom/licenses.txt ("<group:name or prefix*> <SPDX id>", first match wins);
# an unmatched component is recorded as UNKNOWN and fails `check`. Waivers live in tools/sbom/waivers.json.

require 'date'
require 'json'
require 'net/http'
require 'rexml/document'
require 'uri'

require_relative '../lint/dependency_registry'

module Sbom
  GRADLE_METADATA = 'android/gradle/verification-metadata.xml'
  RESOLVED_GLOB = 'macos/Packages/*/Package.resolved'
  SBOM_PATH = 'tools/sbom/sbom.cdx.json'
  LICENSES_PATH = 'tools/sbom/licenses.txt'
  WAIVERS_PATH = 'tools/sbom/waivers.json'
  LICENSE_EXCEPTIONS_PATH = 'tools/sbom/license-exceptions.txt'
  BLOCKING_SEVERITIES = %w[HIGH CRITICAL].freeze
  OSV_BATCH_URL = 'https://api.osv.dev/v1/querybatch'
  OSV_VULN_URL = 'https://api.osv.dev/v1/vulns/'

  Component = Struct.new(:ecosystem, :name, :version, :license, keyword_init: true) do
    def purl
      case ecosystem
      when 'maven'
        group, artifact = name.split(':', 2)
        "pkg:maven/#{group}/#{artifact}@#{version}"
      else
        "pkg:swift/#{name}@#{version}"
      end
    end
  end

  module_function

  def components(repo_root)
    licenses = read_rules(File.join(repo_root, LICENSES_PATH))
    found = gradle_components(repo_root) + swift_components(repo_root)
    found.each { |c| c.license = license_for(c, licenses) }
    found.uniq { |c| [c.ecosystem, c.name, c.version] }
         .sort_by { |c| [c.ecosystem, c.name, c.version] }
  end

  def gradle_components(repo_root)
    path = File.join(repo_root, GRADLE_METADATA)
    return [] unless File.exist?(path)

    REXML::Document.new(File.read(path)).get_elements('//components/component').map do |el|
      Component.new(ecosystem: 'maven',
                    name: "#{el.attributes['group']}:#{el.attributes['name']}",
                    version: el.attributes['version'])
    end
  end

  def swift_components(repo_root)
    Dir.glob(File.join(repo_root, RESOLVED_GLOB)).sort.flat_map do |path|
      JSON.parse(File.read(path)).fetch('pins', []).filter_map do |pin|
        version = pin.dig('state', 'version') || pin.dig('state', 'revision')
        next unless version

        Component.new(ecosystem: 'swift', name: swift_name(pin['location'], pin['identity']), version: version)
      end
    end
  end

  def swift_name(location, identity)
    return identity unless location

    location.sub(%r{\A[a-z]+://}, '').delete_suffix('.git')
  end

  def read_rules(path)
    return [] unless File.exist?(path)

    File.readlines(path, chomp: true).filter_map do |line|
      line = line.sub(/#.*/, '').strip
      line.split(/\s+/, 2) unless line.empty?
    end
  end

  def license_for(component, rules)
    key = component.name
    rule = matching_rule(rules, key)
    rule ? rule[1] : 'UNKNOWN'
  end

  def matching_rule(rules, key)
    rules.find { |pattern, _| pattern.end_with?('*') ? key.start_with?(pattern.chomp('*')) : key == pattern }
  end

  def document(components)
    {
      'bomFormat' => 'CycloneDX',
      'specVersion' => '1.5',
      'version' => 1,
      'metadata' => { 'component' => { 'type' => 'application', 'name' => 'tandem' } },
      'components' => components.map { |c| component_entry(c) }
    }
  end

  def component_entry(component)
    {
      'type' => 'library',
      'bom-ref' => component.purl,
      'name' => component.name,
      'version' => component.version,
      'purl' => component.purl,
      'licenses' => [{ 'license' => { 'id' => component.license } }]
    }
  end

  def render(repo_root)
    "#{JSON.pretty_generate(document(components(repo_root)))}\n"
  end

  # Returns error strings; empty means the committed SBOM is current and every license is allowed.
  def check(repo_root)
    path = File.join(repo_root, SBOM_PATH)
    return ["#{SBOM_PATH} is missing; run `ruby tools/sbom/sbom.rb generate`"] unless File.exist?(path)

    errors = []
    unless File.read(path) == render(repo_root)
      errors << "#{SBOM_PATH} is stale; run `ruby tools/sbom/sbom.rb generate` and commit it"
    end
    exceptions = read_rules(File.join(repo_root, LICENSE_EXCEPTIONS_PATH))
    errors + license_errors(JSON.parse(File.read(path)), exceptions)
  end

  def license_errors(sbom, exceptions = [])
    sbom.fetch('components', []).filter_map do |entry|
      license = entry.dig('licenses', 0, 'license', 'id')
      if license.nil?
        "#{entry['purl']}: no license field"
      elsif license != 'UNKNOWN' && matching_rule(exceptions, entry['name'])
        nil
      elsif !DependencyRegistry::ALLOWED_LICENSES.include?(license)
        "#{entry['purl']}: license '#{license}' is not on the allowlist (#{DependencyRegistry::ALLOWED_LICENSES.join(', ')})"
      end
    end
  end

  # advisories: { purl => [{ 'id' => ..., 'severity' => ... }] }. Returns error strings.
  def scan(sbom, advisories, waivers, today)
    errors = []
    waived = {}
    waivers.each do |waiver|
      if Date.parse(waiver.fetch('expires')) < today
        errors << "waiver #{waiver['id']} expired #{waiver['expires']}; fix the dependency or renew with a reason"
      else
        waived[waiver['id']] = true
      end
    end

    sbom.fetch('components', []).each do |entry|
      advisories.fetch(entry['purl'], []).each do |advisory|
        severity = advisory['severity'].to_s.upcase
        next unless BLOCKING_SEVERITIES.include?(severity)
        next if waived[advisory['id']]

        errors << "#{entry['purl']}: #{advisory['id']} (#{severity}) is not waived"
      end
    end
    errors
  end

  def read_waivers(repo_root)
    path = File.join(repo_root, WAIVERS_PATH)
    File.exist?(path) ? JSON.parse(File.read(path)) : []
  end

  def osv_advisories(sbom)
    purls = sbom.fetch('components', []).map { |entry| entry['purl'] }
    hits = purls.each_slice(500).flat_map do |slice|
      response = post_json(OSV_BATCH_URL, { 'queries' => slice.map { |purl| { 'package' => { 'purl' => purl } } } })
      response.fetch('results').map { |result| (result['vulns'] || []).map { |v| v['id'] } }
    end
    details = hits.flatten.uniq.to_h { |id| [id, get_json("#{OSV_VULN_URL}#{id}")] }
    purls.zip(hits).to_h do |purl, ids|
      [purl, ids.map { |id| { 'id' => id, 'severity' => osv_severity(details[id]) } }]
    end
  end

  # Unrated advisories fail closed as HIGH.
  def osv_severity(vuln)
    vuln.dig('database_specific', 'severity') || 'HIGH'
  end

  def post_json(url, body)
    uri = URI(url)
    response = Net::HTTP.post(uri, JSON.generate(body), 'Content-Type' => 'application/json')
    raise "OSV request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def get_json(url)
    response = Net::HTTP.get_response(URI(url))
    raise "OSV request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def report(label, errors)
    if errors.empty?
      puts "#{label}: OK"
      0
    else
      warn "#{label}: FAILED\n\n#{errors.map { |e| "  #{e}" }.join("\n")}"
      1
    end
  end

  def run(argv, repo_root, today: Date.today)
    command = argv.shift
    case command
    when 'generate'
      File.write(File.join(repo_root, SBOM_PATH), render(repo_root))
      puts "wrote #{SBOM_PATH}"
      0
    when 'check'
      report('SBOM check', check(repo_root))
    when 'scan'
      sbom = JSON.parse(File.read(File.join(repo_root, SBOM_PATH)))
      option = argv.index('--advisories')
      advisories = option ? JSON.parse(File.read(argv[option + 1])) : osv_advisories(sbom)
      report('Vulnerability scan', scan(sbom, advisories, read_waivers(repo_root), today))
    else
      warn 'usage: sbom.rb generate|check|scan [--advisories FILE]'
      2
    end
  end
end

exit Sbom.run(ARGV, File.expand_path('../..', __dir__)) if $PROGRAM_NAME == __FILE__
