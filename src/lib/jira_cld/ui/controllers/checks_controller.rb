# frozen_string_literal: true

module JiraCld
  module UI
    module Controllers
      class ChecksController < BaseController
        def index(project = nil)
          project ||= active_project
          render "checks/index", { project: project, checks: project ? checks_for(project) : [] }
        end

        private

        def checks_for(project)
          config = config_for(project.id)
          checks = []
          checks << { name: "config", status: "ok", detail: config.config_path }
          checks << { name: "project", status: "ok", detail: project.id }
          checks << { name: "jira", status: config.jira_api_token || config.jira_pat ? "ok" : "warn",
                      detail: config.jira_base_url }
          checks << { name: "confluence", status: config.kb_enabled? ? "ok" : "warn",
                      detail: config.confluence_base_url.to_s }
          begin
            DB.setup!(config)
            checks << { name: "sqlite", status: DB.integrity_check == "ok" ? "ok" : "fail",
                        detail: "#{config.db_path} #{DB.size_bytes} bytes" }
          rescue StandardError => e
            checks << { name: "sqlite", status: "fail", detail: e.message }
          end
          checks
        end
      end
    end
  end
end
