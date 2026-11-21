# frozen_string_literal: true

require "digest"
require "json"

module JiraCache
  class KeyBuilder
    def initialize(user:, project:, connections: [])
      @user = user
      @project = project
      @connections = Array(connections).compact
    end

    def key(namespace, logical)
      "#{prefix(namespace)}#{digest(logical)}"
    end

    def prefix(namespace = nil)
      base = "jira:v1:u#{@user.id}:p#{@project.id}:g#{@project.cache_generation}:c#{connection_scope}:"
      namespace ? "#{base}#{namespace}:" : base
    end

    private

    def connection_scope
      @connections.map(&:id).sort.join("-").presence || "none"
    end

    def digest(logical)
      Digest::SHA256.hexdigest(canonical(logical))
    end

    def canonical(value)
      case value
      when Hash
        JSON.generate(deep_sort(value))
      when Array
        JSON.generate(value.map { |item| item.is_a?(Hash) ? deep_sort(item) : item })
      else
        value.to_s
      end
    end

    def deep_sort(value)
      case value
      when Hash
        value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, deep_sort(value[key])] }
      when Array
        value.map { |item| deep_sort(item) }
      else
        value
      end
    end
  end
end
