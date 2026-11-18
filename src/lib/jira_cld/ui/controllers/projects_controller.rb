# frozen_string_literal: true

module JiraCld
  module UI
    module Controllers
      class ProjectsController < BaseController
        def index
          render "projects/index", { projects: projects, active_project: active_project }
        end

        def new
          render "projects/new", { project: nil, form_action: "/projects",
                                   title: t("Новый проект", "New project") }
        end

        def create
          require_csrf!
          id = params["id"].to_s.strip
          raise ConfigError, "project id is required" if id.empty?

          project = registry.add(
            "id" => id,
            "name" => params["name"].to_s.empty? ? id : params["name"],
            "jira_keys" => split_list(params["jira_keys"]),
            "spaces" => split_list(params["spaces"]),
            "style" => params["style"] || "scrum",
            "related_scopes" => [],
            "queries" => default_queries,
            "team" => { "show_email" => false, "channels" => [] }
          )
          create_project_dir(project)
          Stats::Writer.new(config_for(project.id)).audit(
            action: "project_add", source: "ui", detail: { project_id: project.id }
          )
          context.set_cookie("jira_cld_project", project.id)
          flash("/projects/#{project.id}", notice: t("Проект создан", "Project created"))
        rescue StandardError => e
          flash("/projects/new", error: e.message)
        end

        def show(id)
          project = find_project!(id)
          context.set_cookie("jira_cld_project", project.id)
          OverviewController.new(context).show(project)
        end

        def edit(id)
          render "projects/edit", { project: find_project!(id), form_action: "/projects/#{id}",
                                    title: t("Редактировать проект", "Edit project") }
        end

        def update(id)
          require_csrf!
          project = find_project!(id)
          registry.update(
            id,
            "name" => params["name"].to_s.empty? ? project.name : params["name"],
            "jira_keys" => split_list(params["jira_keys"]),
            "spaces" => split_list(params["spaces"]),
            "style" => params["style"] || project.style
          )
          Stats::Writer.new(config_for(id)).audit(
            action: "project_update", source: "ui", detail: { project_id: id }
          )
          flash("/projects/#{id}", notice: t("Сохранено", "Saved"))
        rescue StandardError => e
          flash("/projects/#{id}/edit", error: e.message)
        end

        def confirm_destroy(id)
          render "projects/delete", project: find_project!(id)
        end

        def destroy(id)
          require_csrf!
          project = find_project!(id)
          return flash("/projects", error: t("Активный проект удалить нельзя", "Cannot delete the active project")) if active_project&.id == id
          return flash("/projects/#{id}", error: t("Подтверждение не совпадает", "Confirmation does not match")) unless params["confirm"] == id

          Stats::Writer.new(config_for(project.id)).audit(
            action: "project_remove", source: "ui", detail: { project_id: project.id, soft_delete: true }
          )
          registry.remove(project.id)
          flash("/projects", notice: t("Проект перемещён в .trash", "Project moved to .trash"))
        rescue StandardError => e
          flash("/projects", error: e.message)
        end

        def select(id)
          project = find_project!(id)
          context.set_cookie("jira_cld_project", project.id)
          redirect("/projects/#{project.id}")
        end
      end
    end
  end
end
