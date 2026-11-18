# frozen_string_literal: true

module JiraCld
  module UI
    module Controllers
      class CacheController < BaseController
        def show(id)
          project = find_project!(id)
          config = config_for(id)
          begin
            DB.setup!(config)
            render "cache/show", { project: project, rows: DB.stats, bytes: DB.size_bytes,
                                   db_path: config.db_path, error: nil }
          rescue StandardError => e
            render "cache/show", { project: project, rows: [], bytes: 0,
                                   db_path: config.db_path, error: e.message }
          end
        end

        def clear(id)
          require_csrf!
          project = find_project!(id)
          config = config_for(id)
          DB.setup!(config)
          store = Cache::DatabaseStore.new(
            max_bytes: config.cache_max_bytes,
            stale_grace: config.cache_stale_grace,
            max_entry_bytes: config.cache_max_entry_bytes
          )
          expired = params["scope"] == "expired"
          store.clear(namespace: params["namespace"], expired: expired)
          DB.checkpoint("TRUNCATE")
          Stats::Writer.new(config).audit(
            action: "cache_clear", source: "ui",
            detail: { namespace: params["namespace"], scope: params["scope"] }
          )
          flash("/projects/#{project.id}/cache", notice: t("Кэш очищен", "Cache cleared"))
        rescue StandardError => e
          flash("/projects/#{project.id}/cache", error: e.message)
        end
      end
    end
  end
end
