# frozen_string_literal: true

module JiraCore
  class SecretError < StandardError
    attr_reader :code

    def initialize(message, code: :secret_unresolved)
      super(message)
      @code = code
    end
  end
end
