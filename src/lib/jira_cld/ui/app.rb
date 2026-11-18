# frozen_string_literal: true

require "securerandom"
require "erubi"

module JiraCld
  module UI
    class App
      def self.run(config:, env: ENV, port: nil)
        require "puma"
        require "rack"

        Router.opts[:env] = env
        Router.opts[:config_path] = config.config_path
        Router.opts[:theme] = config.ui_theme
        Router.opts[:locale] = config.ui_locale
        Router.opts[:root] = JiraCld.root
        token = SecureRandom.hex(24)
        Router.opts[:token] = token

        server = Puma::Server.new(Router)
        bind_port = port || config.ui_port
        bind_host = config.ui_host
        server.add_tcp_listener(bind_host, bind_port)
        actual_port = begin
          server.binder.ios.first.local_address.ip_port
        rescue StandardError
          bind_port
        end
        display_host = case bind_host
                       when "0.0.0.0" then "127.0.0.1"
                       when "::" then "[::1]"
                       else bind_host
                       end
        url = "http://#{display_host}:#{actual_port}/?token=#{token}"
        $stdout.puts("jira-cld UI: #{url}")
        $stdout.flush
        open_browser(url) if config.ui_open? && env["JIRA_CLD_NO_OPEN"].nil?
        %w[INT TERM].each do |signal|
          Signal.trap(signal) { Thread.new { server.stop(true) } }
        end
        server.run.join
      end

      def self.open_browser(url)
        return unless $stdout.tty?

        command = if system("command -v xdg-open >/dev/null 2>&1")
                    ["xdg-open", url]
                  elsif system("command -v open >/dev/null 2>&1")
                    ["open", url]
                  end
        Process.detach(Process.spawn(*command, out: File::NULL, err: File::NULL)) if command
      rescue StandardError
        nil
      end
    end
  end
end
