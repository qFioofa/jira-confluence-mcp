# frozen_string_literal: true

require "cgi"

module JiraCld
  module UI
    module Helpers
      class ApplicationHelper
        def initialize(context)
          @context = context
        end

        def t(ru, en)
          @context.locale == "en" ? en : ru
        end

        def h(value)
          CGI.escapeHTML(value.to_s)
        end

        def csrf_field
          %(<input type="hidden" name="csrf" value="#{h(@context.csrf)}">)
        end

        def status_class(status)
          case status.to_s
          when "ok" then "status-ok"
          when "warn" then "status-warn"
          when "fail", "error" then "status-fail"
          else "muted"
          end
        end

        def status_label(status)
          "[#{status}]"
        end

        def project_tabs(project, active)
          return "" unless project

          tabs = [
            ["Overview", "/projects/#{project.id}", "overview"],
            ["Cache", "/projects/#{project.id}/cache", "cache"],
            ["Checks", "/projects/#{project.id}/checks", "checks"]
          ]
          links = tabs.map do |label, path, key|
            klass = key == active ? "active" : ""
            %(<a class="#{klass}" href="#{path}">#{label}</a>)
          end
          links << %(<a href="/projects/#{project.id}/edit">#{t("Edit", "Edit")}</a>)
          %(<div class="tabs">#{links.join}</div>)
        end

        def project_selector
          projects = @context.projects
          return "" if projects.empty?

          options = projects.map do |project|
            selected = @context.active_project&.id == project.id ? " selected" : ""
            %(<option value="#{h(project.id)}"#{selected}>#{h(project.name)}</option>)
          end
          %(<form method="get" action="/projects" class="inline"><select name="project_id" ) +
            %(aria-label="Project">#{options.join}</select><noscript><button type="submit">Open</button></noscript></form>)
        end

        def locale_link
          next_locale = @context.locale == "ru" ? "en" : "ru"
          %(<a href="/locale/#{next_locale}?return_to=#{h(CGI.escape(@context.path))}">#{next_locale.upcase}</a>)
        end

        def theme_link
          next_theme = @context.theme == "dark" ? "light" : "dark"
          %(<a href="/theme/#{next_theme}?return_to=#{h(CGI.escape(@context.path))}" aria-label="Toggle theme">◐</a>)
        end

        def format_bytes(bytes)
          value = bytes.to_i
          return "#{value} B" if value < 1024
          return "#{(value / 1024.0).round(1)} KB" if value < 1024 * 1024

          "#{(value / (1024.0 * 1024)).round(1)} MB"
        end

        def partial(name, locals = {})
          View.new(@context).partial(name, locals)
        end

        def nav_link(path, label, active)
          klass = active ? "active" : ""
          %(<a class="#{klass}" href="#{path}">#{h(label)}</a>)
        end
      end
    end
  end
end
