# frozen_string_literal: true

require "mcp"

MCP.configure do |configuration|
  configuration.protocol_version = "2025-11-25"
  configuration.validate_tool_call_arguments = true
  configuration.validate_tool_call_results = false
end

Rails.application.config.x.mcp_allowed_hosts =
  ENV.fetch("MCP_ALLOWED_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
