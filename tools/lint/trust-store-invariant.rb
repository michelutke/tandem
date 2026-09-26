#!/usr/bin/env ruby
# frozen_string_literal: true

# E13-11: Trust-store invariant check — verify every public trust-store lookup/delete method
# takes SpkiFingerprint as its sole key (invariant 3: "Trust is bound to SPKI fingerprints only").
#
#   ruby tools/lint/trust-store-invariant.rb <package-path>  # check a specific package
#   ruby tools/lint/trust-store-invariant.rb                 # check TandemStore
#
# Parses the TrustStore source file and ensures lookup/delete methods use only SpkiFingerprint
# parameters (never hostname, IP, or device ID keys).

require 'pathname'

module TrustStoreInvariant
  # Lookup and delete operations that must key on fingerprint only
  LOOKUP_DELETE_METHODS = %w[get delete unpair].freeze

  module_function

  def check(package_path)
    # Find TrustStore.swift in any Sources subdirectory (for fixtures or main package)
    trust_store_file = Dir.glob(File.join(package_path, 'Sources', '**', 'TrustStore.swift')).first ||
                       Dir.glob(File.join(package_path, 'Sources', '**', '*TrustStore.swift')).first

    return ["TrustStore.swift not found in #{package_path}"] unless trust_store_file

    source = File.read(trust_store_file)
    errors = validate_trust_store_api(source)

    errors
  end

  def validate_trust_store_api(source)
    errors = []

    # Find all public func declarations matching lookup/delete pattern
    # Match: public func get(_ fingerprint: SpkiFingerprint) -> PeerRecord?
    #        public func delete(_ fingerprint: SpkiFingerprint)
    LOOKUP_DELETE_METHODS.each do |method_name|
      # Match public func with method name, capture the parameter list
      pattern = /public\s+func\s+#{method_name}\s*\((.*?)\)/m
      matches = source.scan(pattern)

      matches.each do |params_str|
        params_str = params_str.first
        unless valid_fingerprint_parameters?(params_str)
          errors << "TrustStore.#{method_name}: lookup/delete methods must take " \
                    "only SpkiFingerprint as their sole key parameter. Found: #{params_str.strip}"
        end
      end
    end

    errors
  end

  def valid_fingerprint_parameters?(param_str)
    # Parameter should be: _ fingerprint: SpkiFingerprint
    # or similar patterns that have exactly one parameter of type SpkiFingerprint
    return false if param_str.strip.empty?

    # Remove leading underscore if present (unnamed parameter)
    cleaned = param_str.gsub(/^\s*_\s*/, '')

    # Check that the only parameter is of type SpkiFingerprint
    # Allow for optional default values, but the type must be SpkiFingerprint
    cleaned.match?(/^\s*\w+\s*:\s*SpkiFingerprint\s*$/) ||
      cleaned.match?(/^\s*\w+\s*:\s*SpkiFingerprint\s*=\s*/)
  end
end

if $PROGRAM_NAME == __FILE__
  repo_root = File.expand_path(File.join(__dir__, '..', '..'))
  package_path = File.expand_path(ARGV[0] || File.join(repo_root, 'macos', 'Packages', 'TandemStore'))

  errors = TrustStoreInvariant.check(package_path)

  if errors.empty?
    puts 'trust-store invariant check: OK'
    exit 0
  else
    warn "trust-store invariant check: FAILED\n\n#{errors.map { |e| "  #{e}" }.join("\n")}"
    exit 1
  end
end
