# frozen_string_literal: true

# E00-11 tdd:
#   ci: pathFilter_prTouchesAndroidOnly_macosWorkflowSkipped
#   ci: pathFilter_prTouchesMacosOnly_androidWorkflowSkipped
#   ci: pathFilter_prTouchesProto_allFourWorkflowsRun
#   ci: pathFilter_prTouchesDocsOnly_noWorkflowRuns

require 'minitest/autorun'
require_relative '../check_path_filters'

class CheckPathFiltersTest < Minitest::Test
  FOUR = %w[android conformance macos protocol].freeze

  def run_for(files) = PathFilters.triggered(files) & FOUR

  def test_pathFilter_prTouchesAndroidOnly_macosWorkflowSkipped
    assert_equal %w[android], run_for(%w[android/app/build.gradle.kts android/core/crypto/README.md])
  end

  def test_pathFilter_prTouchesMacosOnly_androidWorkflowSkipped
    assert_equal %w[macos], run_for(%w[macos/TandemApp/TandemApp.swift])
  end

  def test_pathFilter_prTouchesProto_allFourWorkflowsRun
    assert_equal FOUR, run_for(%w[protocol/proto/tandem/v1/placeholder.proto])
  end

  def test_pathFilter_prTouchesDocsOnly_noWorkflowRuns
    assert_empty run_for(%w[docs/protocol/SPEC.md README.md])
  end

  def test_globToRegex_singleStar_doesNotCrossDirectories
    refute_match PathFilters.glob_to_regex('protocol/*.yaml'), 'protocol/proto/buf.yaml'
    assert_match PathFilters.glob_to_regex('protocol/*.yaml'), 'protocol/buf.yaml'
  end
end
