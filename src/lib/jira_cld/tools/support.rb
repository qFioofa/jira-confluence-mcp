# frozen_string_literal: true

require "json"

module JiraCld
  module Tools
    module Support
      module_function

      def ok(payload, limit: nil)
        payload = normalize(payload)
        limit ||= JiraCld.runtime&.config&.output_char_limit || 24_000
        payload, truncated = trim(payload, limit)
        payload["truncated"] = true if truncated
        json = JSON.pretty_generate(payload)
        MCP::Tool::Response.new(
          [{ type: "text", text: json }],
          structured_content: payload
        )
      end

      def error(error, source: nil, limit: nil)
        payload = error_payload(error)
        payload["source"] = source if source
        ok(payload, limit: limit).tap do |response|
          response.instance_variable_set(:@error, true)
        end
      end

      def run(name)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        runtime = JiraCld.runtime
        runtime&.record_tool(name, started, outcome: result.respond_to?(:error?) && result.error? ? "error" : "ok")
        result
      rescue Atlassian::Error => e
        runtime = JiraCld.runtime
        runtime&.record_tool(name, started, outcome: "error")
        runtime&.logger&.warn("tool failed", tool: name, code: e.code.to_s, status: e.status)
        error(e, source: name)
      rescue SecretError => e
        JiraCld.runtime&.record_tool(name, started, outcome: "error")
        error(e, source: name)
      rescue ConfigError => e
        JiraCld.runtime&.record_tool(name, started, outcome: "error")
        error(e, source: name)
      rescue ArgumentError => e
        JiraCld.runtime&.record_tool(name, started, outcome: "error")
        error(e, source: name)
      rescue StandardError => e
        runtime = JiraCld.runtime
        runtime&.record_tool(name, started, outcome: "error")
        runtime&.logger&.error("tool crashed", tool: name, error: e.class.name, message: e.message,
                                               backtrace: e.backtrace&.first(8))
        error(e, source: name)
      end

      def error_payload(error)
        case error
        when Atlassian::QueryError
          {
            "error" => {
              "code" => error.query_code.to_s,
              "message" => error.message,
              "hint" => error.hint
            }.compact
          }
        when Atlassian::Error
          { "error" => error.to_h.transform_keys(&:to_s) }
        when ConfigError
          { "error" => { "code" => "config_error", "message" => error.message } }
        when SecretError
          { "error" => { "code" => "secret_unresolved", "message" => error.message } }
        when ArgumentError
          { "error" => { "code" => "invalid_arguments", "message" => error.message } }
        else
          { "error" => { "code" => "internal_error", "message" => error.message } }
        end
      end

      def normalize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), memo|
            memo[key.to_s] = normalize(item)
          end
        when Array
          value.map { |item| normalize(item) }
        when Symbol
          value.to_s
        else
          value
        end
      end

      def trim(payload, limit)
        json = JSON.generate(payload)
        return [payload, false] if json.bytesize <= limit

        trimmed = payload
        truncated = false
        8.times do
          trimmed = trim_pass(trimmed)
          truncated = true
          break if JSON.generate(trimmed).bytesize <= limit
        end
        [trimmed, truncated]
      end

      def trim_pass(value)
        case value
        when Hash
          result = {}
          value.each do |key, item|
            result[key] = trim_pass(item)
          end
          result["note"] = "output truncated" unless result.key?("note")
          result
        when Array
          keep = value.length <= 2 ? value.length : [(value.length * 0.6).ceil, 1].max
          value.first(keep).map { |item| trim_pass(item) }
        when String
          value.length > 4000 ? "#{value[0, 4000]}\n[truncated]" : value
        else
          value
        end
      end
    end
  end
end
