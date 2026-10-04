# frozen_string_literal: true

#   ci: swiftResolvedSync_aggregatePinDiffers_isReported

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require_relative '../check_swift_resolved_sync'

class CheckSwiftResolvedSyncTest < Minitest::Test
  def write_resolved(dir, name, pins)
    path = File.join(dir, name)
    body = pins.map do |identity, version|
      { 'identity' => identity, 'state' => { 'revision' => "rev-#{version}", 'version' => version } }
    end
    File.write(path, JSON.generate('pins' => body))
    path
  end

  def test_swiftResolvedSync_repoFiles_areInSync
    root = SwiftResolvedSync::ROOT
    assert_empty SwiftResolvedSync.errors(File.join(root, SwiftResolvedSync::AGGREGATE),
                                          Dir.glob(File.join(root, SwiftResolvedSync::PACKAGE_GLOB)))
  end

  def test_swiftResolvedSync_matchingPins_noErrors
    Dir.mktmpdir do |dir|
      aggregate = write_resolved(dir, 'agg.json', 'swift-crypto' => '4.5.2', 'grdb.swift' => '7.11.1')
      package = write_resolved(dir, 'pkg.json', 'swift-crypto' => '4.5.2')
      assert_empty SwiftResolvedSync.errors(aggregate, [package])
    end
  end

  def test_swiftResolvedSync_aggregatePinDiffers_isReported
    Dir.mktmpdir do |dir|
      aggregate = write_resolved(dir, 'agg.json', 'swift-crypto' => '4.5.3')
      package = write_resolved(dir, 'pkg.json', 'swift-crypto' => '4.5.2')
      assert_equal 1, SwiftResolvedSync.errors(aggregate, [package]).size
    end
  end

  def test_swiftResolvedSync_dependencyMissingFromAggregate_isReported
    Dir.mktmpdir do |dir|
      aggregate = write_resolved(dir, 'agg.json', 'swift-crypto' => '4.5.2')
      package = write_resolved(dir, 'pkg.json', 'grdb.swift' => '7.11.1')
      assert_equal 1, SwiftResolvedSync.errors(aggregate, [package]).size
    end
  end
end
