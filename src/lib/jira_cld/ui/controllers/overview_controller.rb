# frozen_string_literal: true

module JiraCld
  module UI
    module Controllers
      class OverviewController < BaseController
        def show(project = nil)
          project ||= active_project
          return redirect("/projects") unless project

          config = config_for(project.id)
          begin
            DB.setup!(config)
            query = Stats::Query.new(config)
            locals = {
              project: project,
              summary: query.summary(project: project.id, range: "1h"),
              recent: query.recent(project: project.id, limit: 12),
              series: query.timeseries(project: project.id, range: "1h", buckets: 40),
              cache: DB.stats,
              bytes: DB.size_bytes,
              db_path: config.db_path
            }
          rescue StandardError => e
            locals = {
              project: project,
              summary: { requests: 0, errors: 0, hit_rate: 0, p50_ms: 0, p95_ms: 0, top_tools: [] },
              recent: [], series: [], cache: [], bytes: 0, db_path: config.db_path, error: e.message
            }
          end
          render "overview/show", locals
        end
      end
    end
  end
end
