# frozen_string_literal: true

class CredentialHealthCheckJob < ApplicationJob
  queue_as :default

  def perform(max_age: 24.hours)
    threshold = max_age.ago
    UserCredential.where("last_verified_at IS NULL OR last_verified_at < ?", threshold)
                  .find_each do |credential|
      CredentialVerifier.new(credential).call
    end
  end
end
