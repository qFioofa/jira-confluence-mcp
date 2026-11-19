# frozen_string_literal: true

require "base64"
require "json"

module JiraMcp
  module Tools
    module Support
      module_function

      def ok(payload, limit: nil)
        payload = normalize(payload)
        limit ||= JiraMcp.runtime&.config&.output_char_limit || 24_000
        payload, truncated = trim(payload, limit)
        payload["truncated"] = true if truncated
        json = JSON.pretty_generate(payload)
        MCP::Tool::Response.new(
          [{ type: "text", text: json }],
          structured_content: payload
        )
      end

      def attachment(data)
        mime = data[:mime_type].to_s
        meta = {
          "id" => data[:id],
          "filename" => data[:filename],
          "mime_type" => mime,
          "size" => data[:size],
          "inline" => data[:inline]
        }.compact
        blocks = []
        if mime.start_with?("image/") && data[:inline]
          blocks << { type: "image", data: Base64.strict_encode64(data[:bytes]), mimeType: mime }
        elsif text_like?(mime) && data[:inline]
          limit = JiraMcp.runtime&.config&.output_char_limit || 24_000
          text = data[:bytes].to_s
          text = "#{text[0, limit]}\n[truncated]" if text.length > limit
          meta["text"] = text
        else
          meta["note"] = "binary content is not inlined"
        end
        blocks << { type: "text", text: JSON.pretty_generate(meta) }
        MCP::Tool::Response.new(blocks, structured_content: meta)
      end

      def text_like?(mime)
        mime.start_with?("text/") || %w[application/json application/xml application/yaml].include?(mime)
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
        runtime = JiraMcp.runtime
        runtime&.record_tool(name, started, outcome: result.respond_to?(:error?) && result.error? ? "error" : "ok")
        result
      rescue JiraCore::Atlassian::Error => e
        runtime = JiraMcp.runtime
        runtime&.record_tool(name, started, outcome: "error")
        runtime&.logger&.warn("tool failed", tool: name, code: e.code.to_s, status: e.status)
        error(e, source: name)
      rescue JiraCore::SecretError => e
        JiraMcp.runtime&.record_tool(name, started, outcome: "error")
        error(e, source: name)
      rescue JiraCore::ConfigError => e
        JiraMcp.runtime&.record_tool(name, started, outcome: "error")
        error(e, source: name)
      rescue ArgumentError => e
        JiraMcp.runtime&.record_tool(name, started, outcome: "error")
        error(e, source: name)
      rescue StandardError => e
        runtime = JiraMcp.runtime
        runtime&.record_tool(name, started, outcome: "error")
        runtime&.logger&.error("tool crashed", tool: name, error: e.class.name, message: e.message,
                                               backtrace: e.backtrace&.first(8))
        error(e, source: name)
      end

      def error_payload(error)
        case error
        when JiraCore::Atlassian::QueryError
          {
            "error" => {
              "code" => error.query_code.to_s,
              "message" => error.message,
              "hint" => error.hint,
              "details" => error.details
            }.compact
          }
        when JiraCore::Atlassian::Error
          { "error" => error.to_h.transform_keys(&:to_s) }
        when JiraCore::ConfigError
          { "error" => { "code" => "config_error", "message" => error.message } }
        when JiraCore::SecretError
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
