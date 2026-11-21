# frozen_string_literal: true

module JiraCore
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
                reference.fetch(:reference, "fields") { field_list }
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

      def boards(**options)
        agile.boards(**options)
      end

      def board_issues(board_id, jql: nil, limit: 50, cursor: nil)
        raw = agile.board_issues(board_id, jql: jql, limit: limit, cursor: cursor)
        {
          issues: Array(raw[:issues]).map { |issue| enforce_scope!(issue) },
          next_cursor: raw[:next_cursor],
          total: raw[:total]
        }
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

      def fields(query: nil, type: nil, custom: nil)
        raw = cached_reference("fields") { field_list }
        list = Array(raw).map { |field| serialize_field(field) }
        unless query.to_s.empty?
          needle = query.to_s.downcase
          list = list.select do |field|
            field[:id].to_s.downcase.include?(needle) || field[:name].to_s.downcase.include?(needle)
          end
        end
        list = list.select { |field| field[:type].to_s == type.to_s } unless type.to_s.empty?
        list = list.select { |field| field[:custom] == !!custom } unless custom.nil?
        { fields: list, total: list.length }
      end

      def field_options(field_id, query: nil, limit: 50)
        limit = clamp_limit(limit)
        response = client.get("#{api_prefix}/field/#{escape_path(field_id)}/context", headers: auth_headers)
        unless response.success?
          return {
            field_id: field_id.to_s,
            options: [],
            total: 0,
            warning: "field contexts are unavailable on this deployment"
          }
        end

        contexts = Array(response.json["values"]).first(5)
        options = contexts.flat_map do |context|
          option_response = client.get(
            "#{api_prefix}/field/#{escape_path(field_id)}/context/#{escape_path(context["id"])}/option",
            query: { startAt: 0, maxResults: limit }, headers: auth_headers
          )
          next [] unless option_response.success?

          Array(option_response.json["values"]).map do |option|
            { id: option["id"], value: option["value"], disabled: option["disabled"] }.compact
          end
        end
        unless query.to_s.empty?
          needle = query.to_s.downcase
          options = options.select { |option| option[:value].to_s.downcase.include?(needle) }
        end
        { field_id: field_id.to_s, options: options.first(limit), total: options.length }
      end

      def transitions(key)
        ensure_scope_key!(key)
        response = client.get("#{api_prefix}/issue/#{escape_path(key)}/transitions",
                              query: { expand: "transitions.fields" }, headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        data = response.json
        transitions = Array(data["transitions"]).map do |transition|
          {
            id: transition["id"],
            name: transition["name"],
            to_id: transition.dig("to", "id"),
            to: transition.dig("to", "name"),
            has_screen: transition["hasScreen"],
            required_fields: required_fields(transition["fields"])
          }.compact
        end
        { key: key.to_s.upcase, transitions: transitions, total: transitions.length }
      end

      def search_users(query, project_key: nil, limit: 20)
        limit = [limit.to_i, 1].max.clamp(1, 50)
        path = if project_key.to_s.empty?
                 "#{api_prefix}/user/search"
               else
                 "#{api_prefix}/user/assignable/search"
               end
        params = { maxResults: limit }
        if config.cloud?
          params[:query] = query.to_s
          params[:project] = project_key.to_s unless project_key.to_s.empty?
        else
          params[:username] = query.to_s
          params[:project] = project_key.to_s unless project_key.to_s.empty?
        end

        response = client.get(path, query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        users = Array(response.json).map { |user| Serialize::Person.compact(user, show_email: config.team_show_email?) }
        { users: users, total: users.length }
      end

      def worklogs(key, limit: 50, cursor: nil)
        limit = clamp_limit(limit)
        ensure_scope_key!(key)
        data = Cursor.decode(cursor) || {}
        params = { startAt: data[:s] || 0, maxResults: limit }
        response = client.get("#{api_prefix}/issue/#{escape_path(key)}/worklog", query: params, headers: auth_headers)
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        payload = response.json
        items = Array(payload["worklogs"])
        start = payload["startAt"].to_i
        total = payload["total"]
        next_start = start + items.length
        more = total ? next_start < total.to_i : items.length >= limit
        {
          key: key.to_s.upcase,
          worklogs: Serialize::Issue.worklogs(items),
          next_cursor: more ? Cursor.encode(k: "jira_worklog", s: next_start) : nil,
          total: total
        }
      end

      def issue_link_types(name_filter: nil)
        data = cached_reference("issue_link_types") do
          response = client.get("#{api_prefix}/issueLinkType", headers: auth_headers)
          Errors.raise_for!(response, domain: :jira, deployment: deployment)
          response.json
        end
        list = Array(data["issueLinkTypes"]).map do |type|
          {
            id: type["id"],
            name: type["name"],
            inward: type["inward"],
            outward: type["outward"]
          }.compact
        end
        unless name_filter.to_s.empty?
          needle = name_filter.to_s.downcase
          list = list.select { |type| type[:name].to_s.downcase.include?(needle) }
        end
        { link_types: list, total: list.length }
      end

      def project_versions(key)
        ensure_scope_project!(key)
        data = cached_reference("project_versions:#{key.to_s.upcase}") do
          response = client.get("#{api_prefix}/project/#{escape_path(key)}/versions", headers: auth_headers)
          Errors.raise_for!(response, domain: :jira, deployment: deployment)
          response.json
        end
        versions = Array(data).map { |version| serialize_version(version) }
        { project: key.to_s.upcase, versions: versions, total: versions.length }
      end

      def project_components(key)
        ensure_scope_project!(key)
        data = cached_reference("project_components:#{key.to_s.upcase}") do
          response = client.get("#{api_prefix}/project/#{escape_path(key)}/components", headers: auth_headers)
          Errors.raise_for!(response, domain: :jira, deployment: deployment)
          response.json
        end
        components = Array(data).map do |component|
          {
            id: component["id"],
            name: component["name"],
            description: component["description"],
            lead: Serialize::Person.compact(component["lead"], show_email: config.team_show_email?),
            assignee_type: component["assigneeType"]
          }.compact
        end
        { project: key.to_s.upcase, components: components, total: components.length }
      end

      def attachment(key, id: nil, filename: nil)
        data = issue(key, fields: %w[attachment summary], rendered: false)
        items = Array(data.dig("fields", "attachment"))
        item = if !id.to_s.empty?
                 items.find { |entry| entry["id"].to_s == id.to_s }
               elsif !filename.to_s.empty?
                 items.find { |entry| entry["filename"].to_s == filename.to_s }
               else
                 items.first
               end
        raise NotFoundError.new("attachment not found on #{key}", domain: :jira, status: 404) unless item

        url = item["content"].to_s
        raise Error.new("attachment has no content URL", code: :attachment_unavailable, domain: :jira) if url.empty?

        response = client.get(url, headers: auth_headers.merge("Accept" => "*/*"))
        Errors.raise_for!(response, domain: :jira, deployment: deployment)
        bytes = response.body.to_s
        {
          id: item["id"],
          filename: item["filename"],
          mime_type: item["mimeType"],
          size: item["size"],
          bytes: bytes,
          content_type: response.headers["content-type"],
          inline: bytes.bytesize <= MAX_INLINE_BYTES
        }
      end

      def capabilities
        {
          deployment: deployment,
          api_prefix: api_prefix,
          search: config.cloud? ? "nextPageToken" : "startAt",
          issues: true,
          agile: true,
          boards: true,
          fields: true,
          transitions: true,
          users: true,
          worklogs: true,
          links: true,
          versions: true,
          comments: true,
          attachments: "metadata+download"
        }
      end

      private

      MAX_INLINE_BYTES = 5 * 1024 * 1024

      def cached_reference(logical, &block)
        return yield unless reference

        reference.fetch(:reference, logical, &block)
      end

      def serialize_field(field)
        {
          id: field["id"],
          name: field["name"],
          custom: field["custom"],
          type: field.dig("schema", "type"),
          items: field.dig("schema", "items"),
          system: field.dig("schema", "system"),
          clause_names: Array(field["clauseNames"]).first(5)
        }.compact
      end

      def serialize_version(version)
        {
          id: version["id"],
          name: version["name"],
          description: version["description"],
          released: version["released"],
          archived: version["archived"],
          start_date: version["startDate"],
          release_date: version["releaseDate"],
          overdue: version["overdue"]
        }.compact
      end

      def required_fields(fields)
        return [] unless fields.is_a?(Hash)

        fields.filter_map do |id, field|
          next unless field.is_a?(Hash) && field["required"]

          {
            id: id,
            name: field["name"],
            type: field.dig("schema", "type"),
            allowed_values: Array(field["allowedValues"]).first(20).filter_map do |value|
              value["value"] || value["name"] || value["id"]
            end
          }.compact
        end
      end

      def ensure_scope_key!(key)
        keys = config.jira_keys
        return key if keys.empty?

        prefix = key.to_s.split("-").first.to_s.upcase
        unless keys.include?(prefix)
          raise Error.new("issue #{key} is outside the project allowlist", code: :scope_forbidden,
                                                                           domain: :jira, hint: "post-filter rejected cross-project data")
        end
        key
      end

      def ensure_scope_project!(key)
        keys = config.jira_keys
        return key if keys.empty?

        unless keys.include?(key.to_s.upcase)
          raise Error.new("project #{key} is outside the project allowlist", code: :scope_forbidden,
                                                                            domain: :jira, hint: "post-filter rejected cross-project data")
        end
        key
      end


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
