# frozen_string_literal: true

module JiraCld
  module UI
    module Routes
      module_function

      def dispatch(context, r)
        r.get "assets", String do |path|
          context.send_asset(path)
        end

        r.get "locale", String do |locale|
          context.set_cookie("jira_cld_locale", %w[ru en].include?(locale) ? locale : "ru")
          context.redirect(context.safe_return_to(context.params["return_to"]))
        end

        r.get "theme", String do |theme|
          context.set_cookie("jira_cld_theme", %w[system light dark].include?(theme) ? theme : "system")
          context.redirect(context.safe_return_to(context.params["return_to"]))
        end

        r.root do
          if context.active_project
            Controllers::OverviewController.new(context).show(context.active_project)
          else
            context.redirect("/projects")
          end
        end

        r.get "projects" do
          Controllers::ProjectsController.new(context).index
        end

        r.on "projects" do
          r.get "new" do
            Controllers::ProjectsController.new(context).new
          end

          r.post true do
            Controllers::ProjectsController.new(context).create
          end

          r.on String do |id|
            r.get true do
              Controllers::ProjectsController.new(context).show(id)
            end

            r.get "select" do
              Controllers::ProjectsController.new(context).select(id)
            end

            r.get "edit" do
              Controllers::ProjectsController.new(context).edit(id)
            end

            r.post true do
              Controllers::ProjectsController.new(context).update(id)
            end

            r.get "cache" do
              Controllers::CacheController.new(context).show(id)
            end

            r.post "cache", "clear" do
              Controllers::CacheController.new(context).clear(id)
            end

            r.get "checks" do
              project = context.projects.find { |item| item.id == id }
              Controllers::ChecksController.new(context).index(project)
            end

            r.get "delete" do
              Controllers::ProjectsController.new(context).confirm_destroy(id)
            end

            r.post "delete" do
              Controllers::ProjectsController.new(context).destroy(id)
            end
          end
        end

        r.get "checks" do
          Controllers::ChecksController.new(context).index
        end

        r.get "settings" do
          Controllers::SettingsController.new(context).show
        end

        r.get "connections" do
          Controllers::SettingsController.new(context).show("connections")
        end

        r.get "diagnostics" do
          Controllers::SettingsController.new(context).show("diagnostics")
        end

        context.halt(404, "not found")
      end
    end
  end
end
