# frozen_string_literal: true

module JiraCld
  module UI
    module Controllers
      class SettingsController < BaseController
        def show(section = nil)
          project = active_project
          config = config_for(project&.id)
          render "settings/#{section || "show"}", { config: config, project: project, section: section }
        end
      end
    end
  end
end
