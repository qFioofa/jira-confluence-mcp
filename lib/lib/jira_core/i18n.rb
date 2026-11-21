# frozen_string_literal: true

require "i18n"

module JiraCore
  module I18n
    SUPPORTED = %w[ru en].freeze
    LOCALES_PATH = File.expand_path("../../config/locales", __dir__)

    module_function

    def setup(locale: "ru", path: nil)
      locale = normalize(locale)
      ::I18n.enforce_available_locales = false
      ::I18n.available_locales = SUPPORTED
      ::I18n.locale = locale
      ::I18n.default_locale = "ru"
      ::I18n.load_path = Dir[File.join(path || LOCALES_PATH, "*.yml")]
      ::I18n.backend.load_translations
      @loaded = true
      locale
    end

    def normalize(locale)
      value = locale.to_s.downcase
      SUPPORTED.include?(value) ? value : "ru"
    end

    def t(key, **options)
      ensure_loaded!
      ::I18n.t(key, **options)
    rescue ::I18n::MissingTranslationData, ::I18n::InvalidLocale
      key.to_s
    end

    def locale
      ::I18n.locale.to_s
    end

    def ensure_loaded!
      return if @loaded

      ::I18n.enforce_available_locales = false
      ::I18n.available_locales = (Array(::I18n.available_locales).map(&:to_s) + SUPPORTED).uniq
      ::I18n.load_path |= Dir[File.join(LOCALES_PATH, "*.yml")]
      ::I18n.backend.load_translations
      @loaded = true
    end
  end
end
