# frozen_string_literal: true

require "json"
require "mcp"

module JiraMcp
  class HTTPApp
    DEFAULT_PATH = "/mcp"

    attr_reader :runtime, :path, :server

    def self.normalize_path(path)
      value = path.to_s
      value = "/#{value}" unless value.start_with?("/")
      value = value.chomp("/") while value.length > 1 && value.end_with?("/")
      value.empty? ? DEFAULT_PATH : value
    end

    def initialize(runtime:, path: DEFAULT_PATH, stateless: true, allowed_hosts: nil, logger: nil)
      @runtime = runtime
      @path = self.class.normalize_path(path)
      @logger = logger || runtime.logger
      @server = JiraMcp::ServerBuilder.build(runtime: runtime)
      @transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        @server,
        stateless: stateless,
        allowed_hosts: allowed_hosts,
        enable_json_response: true
      )
    end

    def call(env)
      case env["PATH_INFO"].to_s
      when path
        JiraMcp.with_runtime(runtime) { @transport.call(env) }
      when "/health"
        health
      else
        [404, { "content-type" => "text/plain; charset=utf-8" }, ["not found\n"]]
      end
    rescue StandardError => e
      @logger&.error("mcp request failed", error: e.class.name, message: e.message)
      [500, { "content-type" => "application/json" }, [JSON.generate(jsonrpc_error)]]
    end

    private

    def health
      [200, { "content-type" => "application/json" },
       [JSON.generate("status" => "ok", "project" => runtime.config.project_id)]]
    end

    def jsonrpc_error
      { jsonrpc: "2.0", error: { code: -32_000, message: "mcp request failed" }, id: nil }
    end
  end
end
