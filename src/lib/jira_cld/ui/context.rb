# frozen_string_literal: true

require "securerandom"

module JiraCld
  module UI
    class Context
      attr_reader :roda, :request, :response, :csrf, :theme, :locale, :notice, :error

      def initialize(roda, request)
        @roda = roda
        @request = request
        @response = roda.response
        @theme = cookie("jira_cld_theme") || opts[:theme] || "system"
        @locale = cookie("jira_cld_locale") || opts[:locale] || "ru"
        @notice = request.params["notice"]
        @error = request.params["error"]
        @csrf = ensure_csrf
      end

      def opts
        roda.class.opts
      end

      def env
        opts[:env] || ENV
      end

      def params
        request.params
      end

      def path
        request.path
      end

      def projects
        @projects ||= config_for(nil).projects
      end

      def active_project
        return @active_project if defined?(@active_project)

        requested = params["project_id"] || cookie("jira_cld_project")
        @active_project = projects.find { |project| project.id == requested } ||
                          projects.find { |project| project.id == config_for(nil).project_id } ||
                          projects.first
        set_cookie("jira_cld_project", @active_project.id) if @active_project && cookie("jira_cld_project") != @active_project.id
        @active_project
      end

      def config_for(project_id = nil)
        Config.load(env: env, config_path: opts[:config_path], project_id: project_id)
      end

      def registry_for
        config_for(nil).registry
      end

      def authorized?
        token = opts[:token]
        !token.nil? && cookie("jira_cld_token") == token
      end

      def authorize!
        return true if authorized?
        return false unless opts[:token] && params["token"] == opts[:token]

        set_cookie("jira_cld_token", params["token"])
        true
      end

      def require_csrf!
        return true if params["csrf"] == cookie("jira_cld_csrf")

        halt(403, "CSRF token mismatch")
      end

      def halt(status, body)
        response.status = status
        response["Content-Type"] = "text/plain; charset=utf-8"
        response.write(body)
        request.halt
      end

      def cookie(name)
        request.cookies[name]
      end

      def set_cookie(name, value, http_only: true)
        response.set_cookie(name, { value: value, path: "/", httponly: http_only, same_site: :strict })
      end

      def redirect(path)
        request.redirect(safe_return_to(path))
      end

      def flash(path, notice: nil, error: nil)
        query = []
        query << "notice=#{CGI.escape(notice)}" if notice
        query << "error=#{CGI.escape(error)}" if error
        target = if query.empty?
                   path
                 else
                   "#{path}#{path.include?("?") ? "&" : "?"}#{query.join("&")}"
                 end
        request.redirect(target)
      end

      def safe_return_to(value)
        path = value.to_s
        path.start_with?("/") && !path.start_with?("//") ? path : "/"
      end

      def security_headers!
        response["Content-Security-Policy"] = "default-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
        response["X-Frame-Options"] = "DENY"
        response["X-Content-Type-Options"] = "nosniff"
        response["Referrer-Policy"] = "no-referrer"
        response["Cache-Control"] = "no-store"
      end

      def send_asset(path)
        root = File.join(opts[:root], "assets", "ui")
        absolute = File.expand_path(path, root)
        unless absolute.start_with?("#{root}/") && File.file?(absolute)
          response.status = 404
          return "not found"
        end
        response["Content-Type"] = mime_type(absolute)
        response["Cache-Control"] = "public, max-age=3600"
        File.binread(absolute)
      end

      def mime_type(path)
        case File.extname(path)
        when ".css" then "text/css; charset=utf-8"
        when ".js" then "application/javascript; charset=utf-8"
        when ".woff2" then "font/woff2"
        when ".png" then "image/png"
        else "application/octet-stream"
        end
      end

      private

      def ensure_csrf
        value = cookie("jira_cld_csrf")
        unless value
          value = SecureRandom.hex(24)
          set_cookie("jira_cld_csrf", value)
        end
        value
      end
    end
  end
end
