# frozen_string_literal: true

class RailsStatsRecorder
  def initialize(user:, project:, connection: nil, logger: Rails.logger)
    @user = user
    @project = project
    @connection = connection
    @logger = logger.is_a?(StructuredLogger) ? logger : StructuredLogger.new(logger)
  end

  def record_tool(tool:, outcome:, duration_ms:, cache: nil)
    ToolCall.create!(
      user: @user,
      project: @project,
      connection: @connection,
      tool: tool.to_s,
      outcome: outcome.to_s,
      duration_ms: duration_ms,
      cache_source: cache,
      created_at: Time.current
    )
  rescue StandardError => e
    @logger&.warn("tool_call write failed: #{e.class}: #{e.message}")
  end
end
