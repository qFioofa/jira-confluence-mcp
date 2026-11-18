# frozen_string_literal: true

require "mcp"

class McpController < ActionController::API
  rate_limit to: 120, within: 1.minute,
             by: -> { McpEndpoint.digest(params[:token].to_s) },
             with: -> { render_mcp_error(:too_many_requests, "rate limit exceeded", data: { code: "rate_limited" }) },
             store: Rails.cache,
             name: "mcp"
  def handle
    endpoint = McpEndpoint.authenticate(params[:token])
    return render_mcp_error(:unauthorized, "invalid or revoked MCP token") unless endpoint

    endpoint.touch_usage!
    runtime = RuntimeBuilder.new(endpoint).build
    server = JiraMcp::ServerBuilder.build(
      runtime: runtime,
      server_context: {
        endpoint: endpoint,
        user: endpoint.user,
        project: endpoint.project
      }
    )
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      allowed_hosts: Rails.application.config.x.mcp_allowed_hosts
    )

    status, headers, body = JiraMcp.with_runtime(runtime) { transport.call(request.env) }
    self.status = status
    headers.each { |key, value| response.headers[key] = value }
    self.response_body = body
  rescue RuntimeBuilder::MissingCredential => e
    render_mcp_error(
      :forbidden,
      "user credential is missing",
      data: {
        code: "user_credential_missing",
        connection_id: e.connection.id,
        project_id: e.project.id,
        connect_url: "/user_credentials/new"
      }
    )
  rescue StandardError => e
    Rails.logger.error("mcp request failed: #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
    render_mcp_error(:internal_server_error, "mcp request failed")
  ensure
    runtime&.close
  end

  private

  def render_mcp_error(status, message, data: nil)
    render json: {
      jsonrpc: "2.0",
      error: { code: -32_000, message: message, data: data }.compact,
      id: nil
    }, status: status
  end
end
