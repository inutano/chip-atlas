# frozen_string_literal: true

require_relative '../test_helper'

# Pins the POST /runs form against the WES config in
# script/sapporo-enrichment-analysis/sapporo_config/. Sapporo 2.4.0 rejects a
# run whose workflow_url is not listed in executable_workflows.json, and since
# 2.2.0 it rejects one without workflow_type_version, so a client that drifts
# from these files breaks every WES submission. No HTTP request is made.
class SapporoServiceTest < Minitest::Test
  CONFIG_DIR = File.expand_path('../../script/sapporo-enrichment-analysis/sapporo_config', __dir__)

  def form
    ChipAtlas::SapporoService.run_request_form({ 'genome' => 'hg38', 'title' => 'My project' })
  end

  def test_workflow_url_is_listed_in_executable_workflows
    listed = JSON.parse(File.read(File.join(CONFIG_DIR, 'executable_workflows.json')))['workflows']
    assert_includes listed, form['workflow_url']
  end

  def test_workflow_type_and_version_are_offered_by_the_service_info
    service_info = JSON.parse(File.read(File.join(CONFIG_DIR, 'service-info.json')))
    versions = service_info.dig('workflow_type_versions', form['workflow_type'], 'workflow_type_version')
    assert_includes versions, form['workflow_type_version']
    assert service_info['workflow_engine_versions'].key?(form['workflow_engine'])
  end

  def test_workflow_engine_parameters_are_never_sent
    # The WES answers 400 to any workflow_engine_parameters while it runs only listed workflows
    refute form.key?('workflow_engine_parameters')
  end

  def test_workflow_params_carry_the_job_parameters_as_json
    assert_equal({ 'genome' => 'hg38', 'title' => 'My project' }, JSON.parse(form['workflow_params']))
  end
end
