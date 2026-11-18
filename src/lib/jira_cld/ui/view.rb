# frozen_string_literal: true

require "erubi"
require "json"

module JiraCld
  module UI
    class View
      ROOT = File.expand_path("../../..", __dir__)

      def initialize(context)
        @context = context
        @helpers = Helpers::ApplicationHelper.new(context)
      end

      def render(template, locals = {}, layout: "application")
        inner = render_template(template, locals)
        return inner unless layout

        render_template("layouts/#{layout}", locals.merge(content: inner))
      end

      def partial(template, locals = {})
        render_template(template, locals)
      end

      private

      def render_template(name, locals)
        path = File.join(ROOT, "lib", "jira_cld", "ui", "views", "#{name}.erb")
        source = Erubi::Engine.new(File.read(path), escape: true).src
        scope = binding
        defaults = {
          project: nil, summary: {}, recent: [], cache: [], bytes: 0, db_path: nil,
          error: nil, projects: [], active_project: nil, title: nil, form_action: nil,
          rows: [], checks: [], config: nil, section: nil, content: nil
        }
        scope.local_variable_set(:context, @context)
        scope.local_variable_set(:helpers, @helpers)
        defaults.merge(locals).each { |key, value| scope.local_variable_set(key, value) }
        eval(source, scope)
      end
    end
  end
end
