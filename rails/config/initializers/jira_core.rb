# frozen_string_literal: true

Rails.application.config.i18n.available_locales = %i[ru en]
Rails.application.config.i18n.default_locale = :en
Rails.application.config.i18n.enforce_available_locales = false
Rails.application.config.i18n.fallbacks = [:en]

core_path = Gem.loaded_specs["jira_core"]&.full_gem_path
if core_path
  Rails.application.config.i18n.load_path += Dir[File.join(core_path, "config", "locales", "*.yml")]
end

I18n.enforce_available_locales = false
I18n.available_locales = %i[ru en]
I18n.locale = ENV.fetch("MCP_LOCALE", "ru").to_sym
