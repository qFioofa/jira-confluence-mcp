# frozen_string_literal: true

require_relative "test_helper"

class QueryTest < CoreTest
  def setup
    super
    @config = config
    @project = @config.project
  end

  def test_jql_wraps_allowlist_and_order
    query = JiraCore::Query::JQL.wrap('text ~ "timeout"', allowlist: ["CLD"])
    assert_equal 'project IN (CLD) AND (text ~ "timeout") ORDER BY updated DESC', query
  end

  def test_jql_rejects_project_and_order_by
    error = assert_raises(JiraCore::Atlassian::QueryError) do
      JiraCore::Query::JQL.wrap("project = EVIL", allowlist: ["CLD"])
    end
    assert_equal :query_scope_forbidden, error.query_code

    error = assert_raises(JiraCore::Atlassian::QueryError) do
      JiraCore::Query::JQL.wrap("status = Open ORDER BY created", allowlist: ["CLD"])
    end
    assert_equal :query_scope_forbidden, error.query_code
  end

  def test_jql_rejects_unbalanced_and_long
    assert_raises(JiraCore::Atlassian::QueryError) do
      JiraCore::Query::JQL.wrap('text ~ "unbalanced', allowlist: ["CLD"])
    end
    assert_raises(JiraCore::Atlassian::QueryError) do
      JiraCore::Query::JQL.wrap("x" * 2001, allowlist: ["CLD"])
    end
  end

  def test_jql_preset
    query, order, limit = JiraCore::Query::JQL.preset(@project, "blocked")
    assert_includes query, "Blocked"
    assert_equal "priority DESC", order
    assert_equal 20, limit
  end

  def test_jql_unknown_preset
    error = assert_raises(JiraCore::Atlassian::QueryError) do
      JiraCore::Query::JQL.preset(@project, "nope")
    end
    assert_equal :query_preset_unknown, error.query_code
  end

  def test_cql_wraps_and_escapes
    cql = JiraCore::Query::CQL.wrap('text ~ "retry"', allowlist: ["CLD"])
    assert_equal 'space IN ("CLD") AND (text ~ "retry") ORDER BY lastmodified DESC', cql

    escaped = JiraCore::Query::CQL.text_query('say "hi" \\ now')
    assert_equal 'text ~ "say \\"hi\\" \\\\ now"', escaped
  end

  def test_cql_rejects_space
    error = assert_raises(JiraCore::Atlassian::QueryError) do
      JiraCore::Query::CQL.wrap("space = EVIL", allowlist: ["CLD"])
    end
    assert_equal :query_scope_forbidden, error.query_code
  end

  def test_jql_structural_builders
    combined = JiraCore::Query::JQL.combine(
      JiraCore::Query::JQL.text_query("retry"),
      JiraCore::Query::JQL.component_query("Backend"),
      "updated >= -30d"
    )
    assert_includes combined, "text ~ \"retry\""
    assert_includes combined, "component = \"Backend\""
  end
end
