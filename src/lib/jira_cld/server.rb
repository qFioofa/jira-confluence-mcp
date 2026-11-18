# frozen_string_literal: true

require "json"
require "mcp"

module JiraCld
  class Server
    PROTOCOL_VERSION = "2025-11-25"

    TOOLS = [
      Tools::ProjectList,
      Tools::ProjectDescribe,
      Tools::ProjectResolve,
      Tools::MyWork,
      Tools::SearchIssues,
      Tools::GetIssue,
      Tools::BriefIssue,
      Tools::GetChangelog,
      Tools::ListAttachments,
      Tools::UnblockIssue,
      Tools::ListSprints,
      Tools::GetSprintIssues,
      Tools::KBSearch,
      Tools::KBGetPage,
      Tools::KBListChildren,
      Tools::TeamWhoKnows,
      Tools::TeamPrepareQuestion,
      Tools::Whoami,
      Tools::CacheStats
    ].freeze

    PROMPTS = [
      Prompts::Daily,
      Prompts::ReleaseNotes,
      Prompts::TaskBrief,
      Prompts::Unblock,
      Prompts::Handoff,
      Prompts::KBAnswer
    ].freeze

    RESOURCE_TEMPLATES = [
      Resources::JiraIssueTemplate,
      Resources::KBPageTemplate
    ].freeze

    attr_reader :runtime, :mcp

    def self.build(config:, logger: nil, runtime: nil)
      runtime ||= Runtime.build(config: config, logger: logger)
      JiraCld.runtime = runtime
      new(runtime: runtime)
    end

    def self.normalize_path(path)
      value = path.to_s
      value = "/#{value}" unless value.start_with?("/")
      value = value.chomp("/") while value.length > 1 && value.end_with?("/")
      value.empty? ? "/mcp" : value
    end

    def initialize(runtime:)
      @runtime = runtime
      @logger = runtime.logger
      configure_mcp
      @mcp = MCP::Server.new(
        name: "ruby-jira-mcp",
        title: "ruby-jira-mcp",
        version: JiraCld::VERSION,
        instructions: I18n.t("server.instructions", project: runtime.config.project_id || "unbound"),
        tools: TOOLS,
        prompts: PROMPTS,
        resource_templates: RESOURCE_TEMPLATES,
        page_size: 50,
        ttl_ms: 60_000,
        cache_scope: "private"
      )
    end

    def run(io: $stdin)
      @transport = MCP::Server::Transports::StdioTransport.new(@mcp)
      install_signal_traps
      @logger.info("mcp server starting", protocol: PROTOCOL_VERSION, project: runtime.config.project_id)
      @transport.open
      self
    ensure
      finalize
    end

    def run_http(host: "127.0.0.1", port: 8765, path: "/mcp", stateless: false, allowed_hosts: nil)
      require "puma"
      require "rack"

      app = http_app(path: path, stateless: stateless, allowed_hosts: allowed_hosts)
      @http_server = Puma::Server.new(app)
      @http_server.add_tcp_listener(host.to_s, Integer(port))
      actual_port = begin
        @http_server.binder.ios.first.local_address.ip_port
      rescue StandardError
        port
      end
      @logger.info(
        "mcp http server starting",
        protocol: PROTOCOL_VERSION,
        project: runtime.config.project_id,
        host: host,
        port: actual_port,
        path: self.class.normalize_path(path),
        stateless: stateless
      )
      $stdout.puts("jira-cld MCP HTTP: http://#{host}:#{actual_port}#{self.class.normalize_path(path)}")
      $stdout.flush
      install_http_signal_traps
      @http_server.run.join
      self
    ensure
      finalize
    end

    def http_app(path: "/mcp", stateless: false, allowed_hosts: nil, enable_json_response: false)
      require "rack"

      normalized = self.class.normalize_path(path)
      @transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        @mcp,
        stateless: stateless,
        allowed_hosts: allowed_hosts,
        enable_json_response: enable_json_response
      )
      transport = @transport
      project = runtime.config.project_id
      lambda do |env|
        case env["PATH_INFO"].to_s
        when normalized
          transport.call(env)
        when "/health"
          [200, { "content-type" => "application/json" }, [JSON.generate("status" => "ok", "project" => project)]]
        else
          [404, { "content-type" => "text/plain; charset=utf-8" }, ["not found\n"]]
        end
      end
    end

    def shutdown
      @http_server&.stop(true)
      finalize
    end

    def tool_names
      mcp.tools.keys
    end

    private

    def configure_mcp
      MCP.configure do |configuration|
        configuration.protocol_version = PROTOCOL_VERSION
        configuration.validate_tool_call_arguments = true
        configuration.validate_tool_call_results = false
        configuration.exception_reporter = lambda do |exception, context|
          @logger.error(
            "mcp exception",
            error: exception.class.name,
            message: exception.message,
            backtrace: exception.backtrace&.first(8),
            context: context
          )
        end
        configuration.around_request = lambda do |data, &handler|
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          request_id = data[:request_id] || data["request_id"]
          method = data[:method] || data["method"]
          tool = data[:tool_name] || data["tool_name"]
          @logger.info("request start", request_id: request_id, method: method, tool: tool)
          begin
            handler.call
          ensure
            duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
            @logger.info("request finish", request_id: request_id, method: method, tool: tool, duration_ms: duration)
          end
        end
      end
    end

    def install_signal_traps
      %w[INT TERM].each do |signal|
        Signal.trap(signal) { exit 0 }
      end
    end

    def install_http_signal_traps
      %w[INT TERM].each do |signal|
        Signal.trap(signal) { Thread.new { @http_server.stop(true) } }
      end
    end

    def finalize
      return if @finalized

      @finalized = true
      begin
        @transport&.close
      rescue StandardError => e
        @logger&.warn("transport close failed", error: e.message)
      end
      @logger.info("mcp server stopping", project: runtime.config.project_id)
      runtime.close
    rescue StandardError => e
      warn("server shutdown failed: #{e.class}: #{e.message}")
      warn(e.backtrace&.first(12)&.join("\n"))
    end
  end
end
