# frozen_string_literal: true

require "json"
require "optparse"

module JiraCld
  module CLI
    module Support
      EXIT = {
        ok: 0,
        config: 2,
        auth: 3,
        not_found: 4,
        db: 5,
        network: 6,
        rate_limited: 7,
        secret: 8,
        capability: 9
      }.freeze

      module_function

      def config(env: ENV, config_path: nil, project_id: nil)
        Config.load(env: env, config_path: config_path, project_id: project_id.nil? ? nil : project_id)
      end

      def global_options(argv)
        options = { config_path: nil, json: false }
        parser = OptionParser.new do |opts|
          opts.on("--config PATH", "config.yml path") { |value| options[:config_path] = value }
          opts.on("--json", "JSON output") { options[:json] = true }
          opts.on("-h", "--help") do
            puts opts
            exit 0
          end
        end
        rest = parser.parse(argv)
        [options, rest]
      end

      def print_json(value)
        $stdout.puts(JSON.pretty_generate(Tools::Support.normalize(value)))
      end

      def print_table(rows, headers = nil)
        return if rows.empty?

        headers ||= rows.first.keys.map(&:to_s)
        widths = headers.to_h do |header|
          [header, [header.length, *rows.map { |row| row[header.to_s].to_s.length }].max]
        end
        $stdout.puts(headers.map { |header| header.ljust(widths[header]) }.join("  "))
        $stdout.puts(headers.map { |header| "-" * widths[header] }.join("  "))
        rows.each do |row|
          $stdout.puts(headers.map { |header| row[header.to_s].to_s.ljust(widths[header]) }.join("  "))
        end
      end

      def fail_with(message, code: :config)
        Kernel.warn("error: #{message}")
        EXIT.fetch(code, 1)
      end

      def warning(message)
        Kernel.warn("warning: #{message}")
      end

      def exit_code_for(error)
        case error
        when ConfigError then EXIT[:config]
        when SecretError then EXIT[:secret]
        when Atlassian::AuthError then EXIT[:auth]
        when Atlassian::NotFoundError then EXIT[:not_found]
        when Atlassian::RateLimitedError then EXIT[:rate_limited]
        when Atlassian::CapabilityError then EXIT[:capability]
        when HTTP::TimeoutError, HTTP::ConnectionError then EXIT[:network]
        else EXIT[:db]
        end
      end
    end
  end
end
