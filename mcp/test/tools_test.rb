# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "open3"

class ToolsTest < McpTest
  def test_exposes_tools_with_annotations
    names = JiraMcp::ServerBuilder::TOOLS.map { |tool| tool.tool_name }
    assert_equal 41, names.length
    %w[project_list project_describe project_resolve
       jira_list_boards jira_get_board_issues jira_list_fields jira_get_field_options
       jira_get_transitions jira_search_users jira_list_link_types jira_project_versions
       jira_project_components git_experts jira_get_issue_links jira_get_worklog jira_get_attachment
       jira_my_work jira_search_issues jira_get_issue
       jira_brief_issue jira_task_context jira_clarify_issue
       jira_get_changelog jira_list_attachments jira_unblock_issue jira_list_sprints
       jira_get_sprint_issues kb_search kb_get_page kb_list_children kb_get_space kb_get_page_history
       kb_get_page_comments kb_list_labels kb_list_attachments kb_get_attachment kb_space_tree
       team_who_knows team_prepare_question
       atlassian_whoami atlassian_cache_stats].each do |name|
      assert_includes names, name
    end

    annotations = JiraMcp::Tools::SearchIssues.annotations_value.to_h
    assert_equal true, annotations[:readOnlyHint]
    assert_equal false, annotations[:destructiveHint]
    assert_equal true, annotations[:idempotentHint]
  end

  def test_project_list_returns_metadata
    response = with_runtime { JiraMcp::Tools::ProjectList.call }
    refute response.error?
    payload = JSON.parse(response.content.first[:text])
    assert_equal "alpha", payload["projects"].first["id"]
    assert_equal "CLD", payload["projects"].first["key"]
  end

  def test_project_resolve_never_binds
    response = with_runtime { JiraMcp::Tools::ProjectResolve.call(query: "alpha") }
    payload = JSON.parse(response.content.first[:text])
    assert_equal "alpha", payload["candidates"].first["id"]
    assert_equal false, payload["needs_confirmation"]
    assert_equal "alpha", payload["bound_project"]
  end

  def test_domain_error_is_structured
    response = with_runtime { JiraMcp::Tools::SearchIssues.call }
    assert response.error?
    payload = JSON.parse(response.content.first[:text])
    assert_equal "query_invalid", payload.dig("error", "code")
  end

  def test_my_work_falls_back_to_builtin_queries
    stub_request(:get, %r{/rest/api/3/search/jql})
      .to_return(status: 200, body: JSON.generate({ "issues" => [] }), headers: { "Content-Type" => "application/json" })

    response = with_runtime { JiraMcp::Tools::MyWork.call(scope: "assigned", limit: 5) }

    refute response.error?
    payload = JSON.parse(response.content.first[:text])
    assert_equal "assigned", payload["scope"]
    assert_equal "builtin", payload["preset_source"]
  end

  def test_unknown_preset_error_lists_available
    response = with_runtime { JiraMcp::Tools::SearchIssues.call(preset: "nope") }

    assert response.error?
    payload = JSON.parse(response.content.first[:text])
    assert_equal "query_preset_unknown", payload.dig("error", "code")
    assert_includes payload.dig("error", "details", "available_presets"), "my_work"
  end

  def test_cache_stats_does_not_need_network
    response = with_runtime { JiraMcp::Tools::CacheStats.call }
    refute response.error?
    payload = JSON.parse(response.content.first[:text])
    assert payload["cache"]
  end

  def test_output_is_truncated
    response = JiraMcp::Tools::Support.ok({ "big" => "x" * 30_000 }, limit: 5000)
    payload = JSON.parse(response.content.first[:text])
    assert payload["truncated"]
    assert_operator response.content.first[:text].bytesize, :<=, 6000
  end

  def test_input_schemas_have_required_fields
    schema = JiraMcp::Tools::GetIssue.input_schema_value.to_h
    assert_equal ["key"], schema[:required]
    assert_equal "object", schema[:type]
  end

  def test_list_boards_returns_cursor
    stub_request(:get, "https://example.atlassian.net/rest/agile/1.0/board")
      .with(query: hash_including("maxResults" => "1"))
      .to_return(status: 200, body: JSON.generate({
                                                    "values" => [{ "id" => 7, "name" => "CLD board", "type" => "scrum" }],
                                                    "total" => 2
                                                  }), headers: { "Content-Type" => "application/json" })

    response = with_runtime { JiraMcp::Tools::ListBoards.call(limit: 1) }
    refute response.error?
    payload = JSON.parse(response.content.first[:text])
    assert_equal "CLD board", payload["boards"].first["name"]
    refute_nil payload["next_cursor"]
  end

  def test_list_fields_filters
    stub_request(:get, "https://example.atlassian.net/rest/api/3/field")
      .to_return(status: 200, body: JSON.generate([
                                                    { "id" => "summary", "name" => "Summary", "custom" => false,
                                                      "schema" => { "type" => "string" } },
                                                    { "id" => "customfield_1", "name" => "Story Points", "custom" => true,
                                                      "schema" => { "type" => "number" } }
                                                  ]), headers: { "Content-Type" => "application/json" })

    response = with_runtime { JiraMcp::Tools::ListFields.call(custom: true) }
    payload = JSON.parse(response.content.first[:text])
    assert_equal 1, payload["total"]
    assert_equal "customfield_1", payload["fields"].first["id"]
  end

  def test_search_users_returns_people
    stub_request(:get, "https://example.atlassian.net/rest/api/3/user/search")
      .with(query: hash_including("query" => "Ali"))
      .to_return(status: 200, body: JSON.generate([{ "accountId" => "u1", "displayName" => "Alice" }]),
                 headers: { "Content-Type" => "application/json" })

    response = with_runtime { JiraMcp::Tools::SearchUsers.call(query: "Ali") }
    payload = JSON.parse(response.content.first[:text])
    assert_equal "Alice", payload["users"].first["display_name"]
  end

  def test_get_transitions_returns_required_fields
    stub_request(:get, "https://example.atlassian.net/rest/api/3/issue/CLD-1/transitions")
      .with(query: hash_including("expand" => "transitions.fields"))
      .to_return(status: 200, body: JSON.generate({
                                                    "transitions" => [{ "id" => "11", "name" => "Done", "to" => { "name" => "Done" },
                                                                        "fields" => { "resolution" => { "name" => "Resolution", "required" => true,
                                                                                                        "schema" => { "type" => "resolution" } } } }]
                                                  }), headers: { "Content-Type" => "application/json" })

    response = with_runtime { JiraMcp::Tools::GetTransitions.call(key: "CLD-1") }
    payload = JSON.parse(response.content.first[:text])
    assert_equal "resolution", payload["transitions"].first["required_fields"].first["id"]
  end

  def test_get_issue_links
    link = { "type" => { "name" => "Blocks" }, "outwardIssue" => { "key" => "CLD-2" } }
    stub_request(:get, "https://example.atlassian.net/rest/api/3/issue/CLD-1")
      .with(query: hash_including("fields" => "summary,status,issuetype,priority,assignee,reporter,updated,created,labels,components,description,parent,duedate,resolution,resolutiondate,timeestimate,timeoriginalestimate,fixVersions,issuelinks,attachment"))
      .to_return(status: 200, body: JSON.generate({ "key" => "CLD-1", "fields" => { "summary" => "x", "issuelinks" => [link] } }),
                 headers: { "Content-Type" => "application/json" })

    response = with_runtime { JiraMcp::Tools::GetIssueLinks.call(key: "CLD-1") }
    payload = JSON.parse(response.content.first[:text])
    assert_equal "CLD-2", payload["links"].first["key"]
    assert_equal "Blocks", payload["links"].first["type"]
  end

  def test_kb_get_page_history
    stub_request(:get, "https://example.atlassian.net/wiki/api/v2/pages/123")
      .to_return(status: 200, body: JSON.generate({
                                                    "id" => "123", "title" => "Runbook",
                                                    "_links" => { "base" => "https://example.atlassian.net/wiki",
                                                                  "webui" => "/spaces/CLD/pages/123" }
                                                  }), headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/123/version")
      .with(query: hash_including("limit" => "50", "start" => "0"))
      .to_return(status: 200, body: JSON.generate({
                                                    "results" => [{ "number" => 2, "when" => "2026-11-17T10:00:00.000Z",
                                                                    "by" => { "displayName" => "Alice" }, "message" => "edit" }],
                                                    "start" => 0, "total" => 1
                                                  }), headers: { "Content-Type" => "application/json" })

    response = with_runtime { JiraMcp::Tools::KBGetPageHistory.call(page_id: "123") }
    payload = JSON.parse(response.content.first[:text])
    assert_equal 2, payload["versions"].first["number"]
  end

  def test_kb_space_tree_builds_nested_tree
    page = lambda do |id, title, ancestors|
      { "id" => id, "title" => title, "ancestors" => ancestors, "space" => { "key" => "CLD" },
        "_links" => { "base" => "https://example.atlassian.net/wiki", "webui" => "/spaces/CLD/pages/#{id}" } }
    end
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content")
      .with(query: hash_including("spaceKey" => "CLD", "type" => "page"))
      .to_return(status: 200, body: JSON.generate({
                                                    "results" => [
                                                      page.call("1", "Home", []),
                                                      page.call("2", "Child", [{ "id" => "1", "title" => "Home" }]),
                                                      page.call("3", "Grandchild",
                                                                [{ "id" => "1", "title" => "Home" }, { "id" => "2", "title" => "Child" }])
                                                    ], "start" => 0, "total" => 3
                                                  }), headers: { "Content-Type" => "application/json" })

    response = with_runtime { JiraMcp::Tools::KBSpaceTree.call(depth: 2) }
    payload = JSON.parse(response.content.first[:text])
    assert_equal 1, payload["nodes"].length
    assert_equal "Home", payload["nodes"].first["title"]
    assert_equal ["Child"], payload["nodes"].first["children"].map { |node| node["title"] }
  end

  def test_kb_get_attachment_returns_image_content
    stub_request(:get, "https://example.atlassian.net/wiki/api/v2/pages/123")
      .to_return(status: 200, body: JSON.generate({
                                                    "id" => "123", "title" => "Runbook",
                                                    "_links" => { "base" => "https://example.atlassian.net/wiki",
                                                                  "webui" => "/spaces/CLD/pages/123" }
                                                  }), headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/123/child/attachment")
      .with(query: hash_including("limit" => "100"))
      .to_return(status: 200, body: JSON.generate({
                                                    "results" => [{ "id" => "a1", "title" => "diagram.png",
                                                                    "extensions" => { "mediaType" => "image/png", "fileSize" => 4 } }]
                                                  }), headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.atlassian.net/wiki/rest/api/content/123/child/attachment/a1/download")
      .to_return(status: 200, body: "PNG!".b, headers: { "Content-Type" => "image/png" })

    response = with_runtime { JiraMcp::Tools::KBGetAttachment.call(page_id: "123", filename: "diagram.png") }
    image = response.content.first
    assert_equal "image", image[:type]
    assert_equal "image/png", image[:mimeType]
    assert_equal "PNG!", Base64.decode64(image[:data])
  end

  def stub_issue_context
    stub_request(:get, %r{/rest/api/3/issue/CLD-1})
      .to_return(status: 200, body: JSON.generate({
                                                    "id" => "10001", "key" => "CLD-1",
                                                    "fields" => {
                                                      "summary" => "Add retry to checkout",
                                                      "status" => { "name" => "In Progress" },
                                                      "issuetype" => { "name" => "Story" },
                                                      "priority" => { "name" => "High" },
                                                      "assignee" => { "accountId" => "u1", "displayName" => "Alice" },
                                                      "components" => [{ "name" => "API" }],
                                                      "labels" => ["checkout"],
                                                      "description" => "We need retries for checkout."
                                                    }
                                                  }), headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{/rest/api/3/issue/CLD-1/comment})
      .to_return(status: 200, body: JSON.generate({ "comments" => [], "total" => 0, "startAt" => 0 }),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{/rest/api/3/issue/CLD-1/changelog})
      .to_return(status: 200, body: JSON.generate({ "values" => [], "total" => 0, "startAt" => 0 }),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{/rest/api/3/search/jql})
      .to_return(status: 200, body: JSON.generate({ "issues" => [], "total" => 0 }),
                 headers: { "Content-Type" => "application/json" })
  end

  def test_jira_task_context_returns_analysis_scaffold
    stub_issue_context

    response = with_runtime { JiraMcp::Tools::JiraTaskContext.call(key: "CLD-1", sources: ["jira"]) }
    payload = JSON.parse(response.content.first[:text])

    refute response.error?
    assert_equal "CLD-1", payload["issue"]["key"]
    assert_equal "We need retries for checkout.", payload["context"]["goal"]
    assert_includes payload["context_markdown"], "# CLD-1"
    assert(payload["gaps"].any? { |gap| gap["reason"].to_s.include?("acceptance") })
  end

  def test_jira_clarify_issue_returns_blocking_questions
    stub_issue_context

    response = with_runtime do
      JiraMcp::Tools::JiraClarifyIssue.call(key: "CLD-1", include: ["jira"], focus: ["acceptance"])
    end
    payload = JSON.parse(response.content.first[:text])

    refute response.error?
    assert_equal false, payload["readiness"]["can_start"]
    acceptance = payload["questions"].find { |question| question["category"] == "acceptance" }
    assert_equal "blocking", acceptance["priority"]
    assert_includes payload["message_markdown"], "## Blocking"
  end

  def test_git_experts_and_who_knows_use_local_history
    Dir.mktmpdir("jira-mcp-tools-git") do |dir|
      run_git(dir, "init", "-q")
      File.write(File.join(dir, "handler.rb"), "retry\n")
      run_git(dir, "add", ".")
      run_git(dir, "-c", "user.name=Alice", "-c", "user.email=alice@example.com",
              "commit", "-q", "-m", "CLD-1 add handler")

      cfg = JiraCore::Config.new(
        project_id: "alpha", registry: registry, base_url: "https://example.atlassian.net",
        jira_base_url: "https://example.atlassian.net",
        confluence_base_url: "https://example.atlassian.net/wiki",
        jira_email: "dev@example.com", jira_api_token: "test-token",
        confluence_api_token: "test-token", spaces: ["CLD"], jira_keys: ["CLD"],
        git_repos: [{ "id" => "backend", "path" => dir, "jira_keys" => ["CLD"] }]
      )
      rt = JiraCore::Runtime.build(config: cfg, cache: JiraCore::Cache::MemoryStore.new)

      experts = JiraMcp.with_runtime(rt) { JiraMcp::Tools::GitExperts.call(issue_key: "CLD-1") }
      payload = JSON.parse(experts.content.first[:text])
      assert_equal "Alice", payload["experts"].first["git_identity"]["name"]

      people = JiraMcp.with_runtime(rt) do
        JiraMcp::Tools::TeamWhoKnows.call(issue_key: "CLD-1", sources: ["git"])
      end
      people_payload = JSON.parse(people.content.first[:text])
      assert_equal ["git"], people_payload["sources"]
      assert_equal "Alice", people_payload["people"].first["display_name"]
    end
  end

  def run_git(dir, *args)
    stdout, stderr, status = Open3.capture3("git", "-C", dir, *args)
    raise "git #{args.join(" ")} failed: #{stderr}#{stdout}" unless status.success?

    stdout
  end

  def test_get_attachment_returns_image_content
    stub_request(:get, "https://example.atlassian.net/rest/api/3/issue/CLD-1")
      .with(query: hash_including("fields" => "attachment,summary"))
      .to_return(status: 200, body: JSON.generate({
                                                    "key" => "CLD-1",
                                                    "fields" => {
                                                      "summary" => "x",
                                                      "attachment" => [{ "id" => "a1", "filename" => "shot.png",
                                                                         "mimeType" => "image/png", "size" => 4,
                                                                         "content" => "https://example.atlassian.net/secure/attachment/1/shot.png" }]
                                                    }
                                                  }), headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.atlassian.net/secure/attachment/1/shot.png")
      .to_return(status: 200, body: "PNG!".b, headers: { "Content-Type" => "image/png" })

    response = with_runtime { JiraMcp::Tools::GetAttachment.call(key: "CLD-1", filename: "shot.png") }
    image = response.content.first
    assert_equal "image", image[:type]
    assert_equal "image/png", image[:mimeType]
    assert_equal "PNG!", Base64.decode64(image[:data])
  end
end
