# frozen_string_literal: true

require "json"
require "fileutils"

module JiraCld
  module UI
    class BaseController
      attr_reader :context

      def initialize(context)
        @context = context
      end

      def params
        context.params
      end

      def t(ru, en)
        context.locale == "en" ? en : ru
      end

      def render(template, locals = {}, layout: "application")
        View.new(context).render(template, locals, layout: layout)
      end

      def redirect(path)
        context.redirect(path)
      end

      def flash(path, notice: nil, error: nil)
        context.flash(path, notice: notice, error: error)
      end

      def require_csrf!
        context.require_csrf!
      end

      def config_for(project_id = nil)
        context.config_for(project_id)
      end

      def registry
        context.registry_for
      end

      def projects
        context.projects
      end

      def active_project
        context.active_project
      end

      def find_project!(id)
        projects.find { |project| project.id == id } || context.halt(404, "project not found")
      end

      def split_list(value)
        value.to_s.split(",").map(&:strip).reject(&:empty?)
      end

      def default_queries
        Marshal.load(Marshal.dump(ConfigStore::DEFAULT_QUERIES))
      end

      def create_project_dir(project)
        FileUtils.mkdir_p(project.data_dir, mode: 0o700)
        File.chmod(0o700, project.data_dir)
        File.write(project.meta_path, JSON.pretty_generate(project.to_h), perm: 0o600)
      end
    end
  end
end
