# frozen_string_literal: true

require_relative "lib/jira_cld/version"

Gem::Specification.new do |spec|
  spec.name = "jira-cld"
  spec.version = JiraCld::VERSION
  spec.authors = ["jira-cld contributors"]
  spec.summary = "Local read-only MCP server for Jira and Confluence"
  spec.description = "MCP stdio server for Jira Cloud/Data Center and Confluence knowledge bases."
  spec.homepage = "https://github.com/anomalyco/ruby-jira-mcp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files = Dir.chdir(__dir__) do
    Dir[
      "bin/*",
      "lib/**/*.rb",
      "config/**/*",
      "db/**/*",
      "assets/**/*"
    ]
  end
  spec.bindir = "bin"
  spec.executables = %w[jira-cld mcp-jira]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", "~> 8.1"
  spec.add_dependency "activesupport", "~> 8.1"
  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "i18n", "~> 1.15"
  spec.add_dependency "mcp", "~> 1.10"
  spec.add_dependency "ougai", "~> 2.1"
  spec.add_dependency "sqlite3", "~> 2.10"
  spec.add_dependency "zeitwerk", "~> 2.8"

  spec.add_development_dependency "benchmark", "~> 0.5"
  spec.add_development_dependency "bundler-audit", "~> 0.9"
  spec.add_development_dependency "lefthook", "~> 2.2"
  spec.add_development_dependency "memory_profiler", "~> 1.1"
  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "rubocop", "~> 1.91"
  spec.add_development_dependency "rubocop-performance", "~> 1.27"
  spec.add_development_dependency "stackprof", "~> 0.2"
  spec.add_development_dependency "webmock", "~> 3.34"
  spec.metadata["rubygems_mfa_required"] = "true"
end
