# frozen_string_literal: true

module JiraCld
  module Atlassian
    class Jira
      DEFAULT_FIELDS = %w[
        summary status issuetype priority assignee reporter updated created labels components
        description parent duedate resolution resolutiondate timeestimate timeoriginalestimate
        fixVersions issuelinks attachment
      ].freeze

      attr_reader :client, :config, :reference, :agile

      def initialize(client:, config:, reference: nil, logger: nil)
        @client = client
        @config = config
        @reference = reference
        @logger = logger
        @agile = Agile.new(client: client, config: config, logger: logger)
      end

      def deployment
        @config.deployment
      end

      def api_prefix
        @config.cloud? ? "/rest/api/3" : "/rest/api/2"
      end

      def myself
        response = client.get("#{api_prefix}/myself", headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        response.json
      end

      def project(key)
        response = client.get("#{api_prefix}/project/#{escape_path(key)}", headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        response.json
      end

      def field_list
        response = client.get("#{api_prefix}/field", headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        response.json
      end

      def field_map
        return @field_map if @field_map

        raw = if reference
                reference.fetch(:reference) { field_list }
              else
                field_list
              end
        @field_map = Array(raw).to_h { |field| [field["id"], field["name"]] }
      rescue Error
        @field_map = {}
      end

      def statuses
        response = client.get("#{api_prefix}/status", headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        response.json
      end

      def search(jql:, limit: 25, cursor: nil, fields: nil)
        limit = clamp_limit(limit)
        cursor_data = Cursor.decode(cursor) || {}
        params = {
          jql: jql,
          maxResults: limit,
          fields: Array(fields || DEFAULT_FIELDS).join(",")
        }

        path = if config.cloud?
                 params[:nextPageToken] = cursor_data[:t] if cursor_data[:t]
                 "#{api_prefix}/search/jql"
               else
                 params[:startAt] = cursor_data[:s] || 0
                 "#{api_prefix}/search"
               end

        response = client.get(path, query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        data = response.json
        issues = Array(data["issues"]).map { |issue| enforce_scope!(issue) }

        next_cursor = if config.cloud?
                        token = data["nextPageToken"]
                        token && !token.to_s.empty? ? Cursor.encode(k: "jira_search", t: token) : nil
                      else
                        start = data["startAt"].to_i
                        total = data["total"]
                        next_start = start + issues.length
                        more = total ? next_start < total.to_i : issues.length >= limit
                        more ? Cursor.encode(k: "jira_search", s: next_start) : nil
                      end

        {
          issues: issues,
          next_cursor: next_cursor,
          total: data["total"],
          deployment: deployment,
          jql: jql
        }
      end

      def issue(key, fields: nil, rendered: true)
        params = { fields: Array(fields || DEFAULT_FIELDS).join(",") }
        params[:expand] = "renderedFields" if rendered
        response = client.get("#{api_prefix}/issue/#{escape_path(key)}", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        enforce_scope!(response.json)
      end

      def comments(key, limit: 50, cursor: nil)
        limit = clamp_limit(limit)
        data = Cursor.decode(cursor) || {}
        params = { maxResults: limit, startAt: data[:s] || 0 }
        response = client.get("#{api_prefix}/issue/#{escape_path(key)}/comment", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        payload = response.json
        comments = Array(payload["comments"])
        start = payload["startAt"].to_i
        total = payload["total"]
        next_start = start + comments.length
        more = total ? next_start < total.to_i : comments.length >= limit
        {
          comments: Serialize::Issue.comments(comments, show_email: config.team_show_email?),
          next_cursor: more ? Cursor.encode(k: "jira_comments", s: next_start) : nil,
          total: total
        }
      end

      def changelog(key, limit: 50, cursor: nil)
        limit = clamp_limit(limit)
        data = Cursor.decode(cursor) || {}
        params = { maxResults: limit, startAt: data[:s] || 0 }
        response = client.get("#{api_prefix}/issue/#{escape_path(key)}/changelog", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        payload = response.json
        histories = Array(payload["values"] || payload["histories"])
        start = payload["startAt"].to_i
        total = payload["total"]
        next_start = start + histories.length
        more = total ? next_start < total.to_i : histories.length >= limit
        {
          entries: Serialize::Issue.changelog(histories),
          next_cursor: more ? Cursor.encode(k: "jira_changelog", s: next_start) : nil,
          total: total
        }
      end

      def attachments(key)
        data = issue(key, fields: %w[attachment summary updated], rendered: false)
        {
          key: data["key"],
          attachments: Serialize::Issue.attachments(data.dig("fields", "attachment"))
        }
      end

      def boards
        agile.boards
      end

      def sprints(board_id, state: nil)
        agile.sprints(board_id, state: state)
      end

      def sprint_issues(sprint_id, limit: 50, cursor: nil)
        agile.sprint_issues(sprint_id, limit: limit, cursor: cursor)
      end

      def project_metadata(key)
        project = project(key)
        {
          id: project["id"],
          key: project["key"],
          name: project["name"],
          style: project["style"] || project["projectTypeKey"],
          issue_types: Array(project["issueTypes"]).map { |type| { id: type["id"], name: type["name"], subtask: type["subtask"] } },
          components: Array(project["components"]).map { |component| { id: component["id"], name: component["name"] } },
          lead: Serialize::Person.compact(project["lead"], show_email: config.team_show_email?),
          url: "#{config.base_url}/projects/#{project["key"]}"
        }
      end

      def capabilities
        {
          deployment: deployment,
          api_prefix: api_prefix,
          search: config.cloud? ? "nextPageToken" : "startAt",
          issues: true,
          agile: true,
          comments: true,
          attachments: true
        }
      end

      private

      def auth_headers
        Auth.headers(config, service: :jira)
      end

      def enforce_scope!(issue)
        key = issue["key"].to_s
        keys = config.jira_keys
        unless keys.empty? || keys.include?(key.split("-").first.to_s.upcase)
          raise Error.new("issue #{key} is outside the project allowlist", code: :scope_forbidden,
                                                                           domain: :jira, hint: "post-filter rejected cross-project data")
        end
        issue
      end

      def clamp_limit(value)
        value.to_i.clamp(1, 50)
      end

      def escape_path(value)
        require "uri"
        URI.encode_www_form_component(value.to_s)
      end
    end
  end
end
