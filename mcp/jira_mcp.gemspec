# frozen_string_literal: true

require_relative "lib/jira_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "jira_mcp"
  spec.version = JiraMcp::VERSION
  spec.authors = ["ruby-jira-mcp contributors"]
  spec.summary = "MCP tools, prompts and resources for Jira and Confluence"
  spec.description = "Protocol layer shared by the standalone Rack server and the Rails application."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jira_core"
  spec.add_dependency "mcp", "~> 1.10"
  spec.add_dependency "rack", "~> 3.2"
end
