# frozen_string_literal: true

class CredentialCipher
  PURPOSE = "jira_web:user_credential:v1"

  class << self
    def encrypt(value)
      encryptor.encrypt_and_sign(value.to_s)
    end

    def decrypt(value)
      encryptor.decrypt_and_verify(value.to_s)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      nil
    end

    private

    def encryptor
      key = ActiveSupport::KeyGenerator.new(
        Rails.application.secret_key_base,
        iterations: 1_000
      ).generate_key(PURPOSE, 32)
      ActiveSupport::MessageEncryptor.new(key)
    end
  end
end
