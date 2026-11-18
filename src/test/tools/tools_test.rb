# frozen_string_literal: true

require_relative "../test_helper"

class ToolsTest < BaseTest
  def setup
    super
    write_config
    @runtime = JiraCld::Runtime.build(config: config)
    JiraCld.runtime = @runtime
    @server = JiraCld::Server.build(config: config, runtime: @runtime)
  end

  def test_exposes_19_tools_with_annotations
    names = @server.tool_names
    assert_equal 19, names.length
    %w[project_list project_describe project_resolve jira_my_work jira_search_issues jira_get_issue
       jira_brief_issue jira_get_changelog jira_list_attachments jira_unblock_issue jira_list_sprints
       jira_get_sprint_issues kb_search kb_get_page kb_list_children team_who_knows team_prepare_question
       atlassian_whoami atlassian_cache_stats].each do |name|
      assert_includes names, name
    end
    annotations = JiraCld::Tools::SearchIssues.annotations_value.to_h
    assert_equal true, annotations[:readOnlyHint]
    assert_equal false, annotations[:destructiveHint]
    assert_equal true, annotations[:idempotentHint]
  end

  def test_project_list_returns_metadata
    response = JiraCld::Tools::ProjectList.call
    refute response.error?
    payload = JSON.parse(response.content.first[:text])
    assert_equal "alpha", payload["projects"].first["id"]
    assert_equal "CLD", payload["projects"].first["key"]
  end

  def test_project_resolve_never_binds
    response = JiraCld::Tools::ProjectResolve.call(query: "alpha")
    payload = JSON.parse(response.content.first[:text])
    assert_equal "alpha", payload["candidates"].first["id"]
    assert_equal false, payload["needs_confirmation"]
    assert_equal "alpha", payload["bound_project"]
  end

  def test_domain_error_is_structured
    response = JiraCld::Tools::SearchIssues.call
    assert response.error?
    payload = JSON.parse(response.content.first[:text])
    assert_equal "query_invalid", payload.dig("error", "code")
  end

  def test_cache_stats_does_not_need_network
    response = JiraCld::Tools::CacheStats.call
    refute response.error?
    payload = JSON.parse(response.content.first[:text])
    assert payload["cache"]
    assert payload["stats"]
  end

  def test_output_is_truncated
    response = JiraCld::Tools::Support.ok({ "big" => "x" * 30_000 }, limit: 5000)
    payload = JSON.parse(response.content.first[:text])
    assert payload["truncated"]
    assert response.content.first[:text].bytesize <= 6000
  end

  def test_input_schemas_have_required_fields
    schema = JiraCld::Tools::GetIssue.input_schema_value.to_h
    assert_equal ["key"], schema[:required]
    assert_equal "object", schema[:type]
  end
end
