#!/usr/bin/env ruby
# frozen_string_literal: true

# E71-09 (AC-11): debug and release builds must embed byte-identical generated protocol
# descriptors. Compares two directories of generated protocol output (for example the debug and
# release compiled protocol classes, or the generated *.pb.swift trees) file by file: the relative
# path sets and every file's bytes must match.
#
#   ruby tools/release-audit/check-proto-descriptors.rb --debug DIR --release DIR

require 'optparse'
require 'digest'

module ProtoDescriptorCheck
  module_function

  def digests(root)
    Dir.glob('**/*', File::FNM_DOTMATCH, base: root)
       .select { |relative| File.file?(File.join(root, relative)) }
       .to_h { |relative| [relative, Digest::SHA256.file(File.join(root, relative)).hexdigest] }
  end

  def check(debug_root, release_root)
    debug = digests(debug_root)
    release = digests(release_root)
    violations = []
    violations << "no generated files found under #{debug_root}" if debug.empty?
    (debug.keys - release.keys).sort.each { |path| violations << "#{path} is only in the debug build" }
    (release.keys - debug.keys).sort.each { |path| violations << "#{path} is only in the release build" }
    (debug.keys & release.keys).sort.each do |path|
      violations << "#{path} differs between debug and release" unless debug[path] == release[path]
    end
    violations
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = 'usage: check-proto-descriptors.rb --debug DIR --release DIR'
    opts.on('--debug DIR') { |v| options[:debug] = v }
    opts.on('--release DIR') { |v| options[:release] = v }
  end.parse!(ARGV)

  if options[:debug].nil? || options[:release].nil?
    warn 'usage: check-proto-descriptors.rb --debug DIR --release DIR'
    exit 2
  end

  violations = ProtoDescriptorCheck.check(options[:debug], options[:release])
  if violations.empty?
    puts 'proto descriptor check: OK'
  else
    warn "proto descriptor check: FAILED\n#{violations.map { |v| "  #{v}" }.join("\n")}"
    exit 1
  end
end
