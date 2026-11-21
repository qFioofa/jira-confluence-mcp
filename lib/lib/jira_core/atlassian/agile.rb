# frozen_string_literal: true

module JiraCore
  module Atlassian
    class Agile
      PREFIX = "/rest/agile/1.0"

      def initialize(client:, config:, logger: nil)
        @client = client
        @config = config
        @logger = logger
      end

      def boards(project_key: nil, name: nil, type: nil, limit: 50, cursor: nil)
        limit = limit.to_i.clamp(1, 50)
        cursor_data = Cursor.decode(cursor) || {}
        start_at = [cursor_data[:s].to_i, 0].max
        params = { startAt: start_at, maxResults: limit }
        params[:projectKeyOrId] = project_key.to_s unless project_key.to_s.empty?
        params[:name] = name.to_s unless name.to_s.empty?
        params[:type] = type.to_s unless type.to_s.empty?

        response = @client.get("#{PREFIX}/board", query: params, headers: headers)
        Errors.raise_for!(response, domain: :jira, deployment: @config.deployment)
        data = response.json
        items = Array(data["values"]).map do |board|
          {
            id: board["id"],
            name: board["name"],
            type: board["type"],
            location: board.dig("location", "projectKey"),
            project: board.dig("location", "projectName")
          }.compact
        end
        total = data["total"]
        next_start = start_at + items.length
        more = total ? next_start < total.to_i : items.length >= limit
        {
          boards: items,
          total: total,
          next_cursor: more ? Cursor.encode(k: "jira_boards", s: next_start) : nil
        }
      end

      def board_issues(board_id, jql: nil, limit: 50, cursor: nil)
        limit = limit.to_i.clamp(1, 50)
        cursor_data = Cursor.decode(cursor) || {}
        start_at = [cursor_data[:s].to_i, 0].max
        params = { startAt: start_at, maxResults: limit }
        params[:jql] = jql.to_s unless jql.to_s.empty?

        response = @client.get("#{PREFIX}/board/#{board_id}/issue", query: params, headers: headers)
        Errors.raise_for!(response, domain: :jira, deployment: @config.deployment)
        data = response.json
        issues = Array(data["issues"])
        total = data["total"]
        next_start = start_at + issues.length
        more = total ? next_start < total.to_i : issues.length >= limit
        {
          issues: issues,
          total: total,
          next_cursor: more ? Cursor.encode(k: "jira_board_issues", s: next_start) : nil
        }
      end

      def sprints(board_id, state: nil)
        params = { maxResults: 50 }
        params[:state] = state if state
        response = @client.get("#{PREFIX}/board/#{board_id}/sprint", query: params, headers: headers)
        Errors.raise_for!(response, domain: :jira, deployment: @config.deployment)
        data = response.json
        {
          sprints: Array(data["values"]).map do |sprint|
            {
              id: sprint["id"],
              name: sprint["name"],
              state: sprint["state"],
              start: sprint["startDate"],
              end: sprint["endDate"],
              complete: sprint["completeDate"],
              board_id: sprint["originBoardId"]
            }.compact
          end,
          total: data["total"]
        }
      end

      def sprint_issues(sprint_id, limit: 50, cursor: nil)
        limit = limit.to_i.clamp(1, 50)
        cursor_data = Cursor.decode(cursor) || {}
        params = { maxResults: limit, startAt: cursor_data[:s] || 0 }
        response = @client.get("#{PREFIX}/sprint/#{sprint_id}/issue", query: params, headers: headers)
        Errors.raise_for!(response, domain: :jira, deployment: @config.deployment)
        data = response.json
        issues = Array(data["issues"])
        start = data["startAt"].to_i
        total = data["total"]
        next_start = start + issues.length
        more = total ? next_start < total.to_i : issues.length >= limit
        {
          issues: issues,
          next_cursor: more ? Cursor.encode(k: "sprint_issues", s: next_start) : nil,
          total: total
        }
      end

      private

      def headers
        Auth.headers(@config, service: :jira)
      end
    end
  end
end
