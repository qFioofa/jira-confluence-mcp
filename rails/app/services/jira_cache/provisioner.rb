# frozen_string_literal: true

module JiraCache
  class Provisioner
    def self.for_project(project)
      StrategyResolver::DEFAULTS.each do |namespace, defaults|
        strategy = CacheStrategy.find_or_initialize_by(
          project: project,
          user_id: nil,
          connection_id: nil,
          namespace: namespace
        )
        next if strategy.persisted?

        strategy.ttl_seconds = defaults[:ttl]
        strategy.stale_grace_seconds = defaults[:stale] ? 600 : 0
        strategy.enabled = true
        strategy.source = "default"
        strategy.save!
      end
    end
  end
end
