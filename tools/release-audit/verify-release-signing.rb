#!/usr/bin/env ruby
# frozen_string_literal: true

# E71-11: verifies the signature of a release artifact before it is published.
#
#   ruby tools/release-audit/verify-release-signing.rb apk <file.apk> [--expect-sha256 <hex>]
#   ruby tools/release-audit/verify-release-signing.rb mac-app <Tandem.app> [--notarized]
#
# apk:     `apksigner verify --print-certs` must pass, print at least one signer, and no signer may
#          be the Android debug certificate. With --expect-sha256 the signer digest must match.
# mac-app: `codesign --verify --deep --strict` must pass; with --notarized,
#          `xcrun stapler validate` must also pass (a stapled notarization ticket is present).
#
# Tool paths come from APKSIGNER, CODESIGN and XCRUN (default: found on PATH), so the tests can
# substitute stubs.

require 'open3'

module ReleaseSigning
  DEBUG_CERT_DN = /CN=Android Debug\b/.freeze
  SIGNER_DN = /^Signer #\d+ certificate DN: (.+)$/.freeze
  SIGNER_SHA256 = /^Signer #\d+ certificate SHA-256 digest: ([0-9a-f]{64})$/.freeze

  module_function

  # Each check returns [errors, info_lines].
  def verify_apk(apk, expect_sha256: nil, apksigner: ENV.fetch('APKSIGNER', 'apksigner'))
    out, err, status = Open3.capture3(apksigner, 'verify', '--print-certs', apk)
    return [["apksigner verify failed for #{apk}: #{(err + out).strip}"], []] unless status.success?

    dns = out.scan(SIGNER_DN).flatten
    digests = out.scan(SIGNER_SHA256).flatten
    errors = []
    errors << "#{apk}: no signer certificate in apksigner output" if dns.empty?
    dns.grep(DEBUG_CERT_DN).each { |dn| errors << "#{apk}: signed with the Android Debug certificate (#{dn})" }
    if expect_sha256 && !digests.include?(expect_sha256.downcase)
      errors << "#{apk}: expected signer SHA-256 #{expect_sha256.downcase}, got #{digests.join(', ')}"
    end
    [errors, dns.zip(digests).map { |dn, digest| "signer: #{dn} sha256=#{digest}" }]
  end

  def verify_mac_app(app, notarized: false,
                     codesign: ENV.fetch('CODESIGN', 'codesign'), xcrun: ENV.fetch('XCRUN', 'xcrun'))
    out, err, status = Open3.capture3(codesign, '--verify', '--deep', '--strict', '--verbose=2', app)
    return [["codesign verify failed for #{app}: #{(err + out).strip}"], []] unless status.success?
    return [[], ['codesign: valid on disk, strict']] unless notarized

    out, err, status = Open3.capture3(xcrun, 'stapler', 'validate', app)
    return [["stapler validate failed for #{app}: #{(err + out).strip}"], []] unless status.success?

    [[], ['codesign: valid on disk, strict', 'stapler: notarization ticket stapled']]
  end

  def main(argv)
    kind, path, *rest = argv
    unless %w[apk mac-app].include?(kind) && path
      warn 'usage: verify-release-signing.rb apk <file.apk> [--expect-sha256 <hex>] | mac-app <app> [--notarized]'
      return 2
    end
    unless File.exist?(path)
      warn "#{path}: not found"
      return 1
    end

    errors, info =
      if kind == 'apk'
        sha_index = rest.index('--expect-sha256')
        verify_apk(path, expect_sha256: sha_index && rest[sha_index + 1])
      else
        verify_mac_app(path, notarized: rest.include?('--notarized'))
      end
    if errors.empty?
      puts info
      puts "#{path}: release signature verified"
      0
    else
      warn errors
      1
    end
  end
end

exit ReleaseSigning.main(ARGV) if $PROGRAM_NAME == __FILE__
