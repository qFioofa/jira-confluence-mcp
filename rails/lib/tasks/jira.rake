# frozen_string_literal: true

namespace :jira do
  desc "Create default cache strategies for existing projects"
  task cache_provision: :environment do
    count = 0
    Project.find_each do |project|
      JiraCache::Provisioner.for_project(project)
      count += 1
    end
    puts "Provisioned cache strategies for #{count} projects"
  end

  desc "Delete old cache and tool-call metrics"
  task prune_stats: :environment do
    CacheEventRetentionJob.perform_now
    puts "Stats pruned"
  end
end
