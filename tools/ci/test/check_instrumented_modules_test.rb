# frozen_string_literal: true

# E00-33 tdd:
#   ci: instrumentedWorkflow_featureModuleFailingTest_workflowFails

require 'minitest/autorun'
require_relative '../check_instrumented_modules'

class CheckInstrumentedModulesTest < Minitest::Test
  WORKFLOW = File.read(File.join(InstrumentedModules::ROOT, InstrumentedModules::WORKFLOW))

  def test_instrumentedWorkflow_everyInstrumentedModule_isRun
    assert_empty InstrumentedModules.missing(WORKFLOW, InstrumentedModules.modules)
  end

  def test_instrumentedWorkflow_featureModules_areDiscovered
    assert_includes InstrumentedModules.modules, ':feature:notifications'
    assert_includes InstrumentedModules.modules, ':feature:contacts'
  end

  def test_instrumentedWorkflow_featureModuleStepRemoved_isReported
    stripped = WORKFLOW.gsub(':feature:contacts:ciGroupDebugAndroidTest', '')
    assert_equal [':feature:contacts'], InstrumentedModules.missing(stripped, InstrumentedModules.modules)
  end
end
