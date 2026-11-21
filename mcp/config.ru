# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "jira_mcp"

runtime = JiraMcp::LocalRuntime.from_env

run JiraMcp::HTTPApp.new(runtime: runtime)
