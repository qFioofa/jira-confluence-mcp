# frozen_string_literal: true

require "json"

class StructuredLogger
  LEVELS = %i[debug info warn error].freeze

  def initialize(logger)
    @logger = logger
  end

  LEVELS.each do |level|
    define_method(level) do |message = nil, **fields, &block|
      if fields.any?
        @logger.public_send(level, "#{message} #{JSON.generate(fields)}")
      else
        @logger.public_send(level, message, &block)
      end
    end
  end

  def respond_to_missing?(name, include_private = false)
    @logger.respond_to?(name, include_private) || super
  end

  def method_missing(name, *args, **kwargs, &block)
    if @logger.respond_to?(name)
      @logger.public_send(name, *args, **kwargs, &block)
    else
      super
    end
  end
end
