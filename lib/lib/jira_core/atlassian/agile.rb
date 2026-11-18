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

      def boards
        response = @client.get("#{PREFIX}/board", headers: headers)
        Errors.raise_for!(response, domain: :jira, deployment: @config.deployment)
        data = response.json
        {
          boards: Array(data["values"]).map do |board|
            {
              id: board["id"],
              name: board["name"],
              type: board["type"],
              location: board.dig("location", "projectKey")
            }.compact
          end,
          total: data["total"]
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
