# frozen_string_literal: true

require "ougai"

module JiraCld
  module Logging
    module_function

    LEVELS = {
      "trace" => Ougai::Logger::TRACE,
      "debug" => Ougai::Logger::DEBUG,
      "info" => Ougai::Logger::INFO,
      "warn" => Ougai::Logger::WARN,
      "error" => Ougai::Logger::ERROR,
      "fatal" => Ougai::Logger::FATAL
    }.freeze

    def build(config, io: $stderr)
      logger = Ougai::Logger.new(io)
      logger.level = LEVELS.fetch(config.log_level.downcase, Ougai::Logger::INFO)
      logger.formatter = Ougai::Formatters::Bunyan.new("jira-cld")
      logger.with_fields = {
        service: "jira-cld",
        version: JiraCld::VERSION,
        project: config.project_id,
        deployment: config.deployment
      }.compact
      logger
    rescue StandardError
      fallback(io)
    end

    def fallback(io = $stderr)
      require "json"
      logger = Ougai::Logger.new(io)
      logger.formatter = Ougai::Formatters::Bunyan.new("jira-cld")
      logger.level = Ougai::Logger::INFO
      logger
    end

    def child(logger, fields)
      logger.respond_to?(:child) ? logger.child(fields) : logger
    end
  end
end
