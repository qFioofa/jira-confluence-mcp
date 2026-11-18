# frozen_string_literal: true

require "i18n"

module JiraCld
  module I18n
    SUPPORTED = %w[ru en].freeze

    module_function

    def setup(locale: "ru", path: nil)
      locale = normalize(locale)
      ::I18n.enforce_available_locales = false
      ::I18n.available_locales = SUPPORTED
      ::I18n.locale = locale
      ::I18n.default_locale = "ru"
      path ||= File.expand_path("../../config/locales", __dir__)
      ::I18n.load_path = Dir[File.join(path, "*.yml")]
      ::I18n.backend.load_translations
      locale
    end

    def normalize(locale)
      value = locale.to_s.downcase
      SUPPORTED.include?(value) ? value : "ru"
    end

    def t(key, **)
      ::I18n.t(key, **)
    rescue ::I18n::MissingTranslationData
      key.to_s
    end

    def locale
      ::I18n.locale.to_s
    end
  end
end
