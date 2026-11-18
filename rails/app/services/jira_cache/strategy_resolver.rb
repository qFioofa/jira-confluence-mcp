# frozen_string_literal: true

module JiraCache
  class StrategyResolver
    DEFAULTS = {
      "identity" => { ttl: 3_600, stale: false },
      "reference" => { ttl: 21_600, stale: true },
      "issue" => { ttl: 60, stale: false },
      "comments" => { ttl: 120, stale: false },
      "changelog" => { ttl: 120, stale: false },
      "attachments" => { ttl: 300, stale: false },
      "page_meta" => { ttl: 600, stale: true },
      "page" => { ttl: 600, stale: true },
      "page_body" => { ttl: 3_600, stale: true },
      "children" => { ttl: 300, stale: true },
      "search" => { ttl: 45, stale: false },
      "sprint" => { ttl: 300, stale: false },
      "board" => { ttl: 600, stale: false },
      "negative" => { ttl: 30, stale: false }
    }.freeze

    def initialize(project:, user: nil, connections: [])
      @project = project
      @user = user
      @connections = Array(connections).compact
    end

    def ttl(namespace)
      row = find(namespace)
      row ? row.ttl_seconds : default(namespace)[:ttl]
    end

    def stale?(namespace)
      row = find(namespace)
      row ? row.stale_grace_seconds.positive? : default(namespace)[:stale]
    end

    def stale_grace(namespace)
      row = find(namespace)
      return row.stale_grace_seconds if row

      default(namespace)[:stale] ? 600 : 0
    end

    def enabled?(namespace)
      row = find(namespace)
      row ? row.enabled? : true
    end

    def find(namespace)
      return @rows[namespace.to_s] if defined?(@rows)

      scope = CacheStrategy.where(project: @project)
      scope = if @user
                scope.where("user_id IS NULL OR user_id = ?", @user.id)
              else
                scope.where(user_id: nil)
              end
      scope = if @connections.empty?
                scope.where(connection_id: nil)
              else
                ids = @connections.map(&:id)
                scope.where("connection_id IS NULL OR connection_id IN (?)", ids)
              end

      @rows = scope.to_a.each_with_object({}) do |row, memo|
        current = memo[row.namespace]
        memo[row.namespace] = row if current.nil? || specificity(row) > specificity(current)
      end
      @rows[namespace.to_s]
    end

    private

    def default(namespace)
      return { ttl: 21_600, stale: true } if namespace.to_s.start_with?("reference")

      DEFAULTS.fetch(namespace.to_s, { ttl: 60, stale: false })
    end

    def specificity(row)
      (row.user_id ? 2 : 0) + (row.connection_id ? 1 : 0)
    end
  end
end
