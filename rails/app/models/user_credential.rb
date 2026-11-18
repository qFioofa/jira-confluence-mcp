# frozen_string_literal: true

class UserCredential < ApplicationRecord
  belongs_to :user
  belongs_to :connection

  enum :auth_type, { api_token: "api_token", pat: "pat" }, default: :api_token
  enum :status, { unknown: "unknown", ok: "ok", error: "error" }, default: :unknown

  validates :user_id, uniqueness: { scope: :connection_id }
  validates :email, presence: true, if: :api_token?
  validates :secret_ciphertext, presence: true, on: :create
  validate :connection_belongs_to_user_team

  def secret
    return if secret_ciphertext.blank?

    CredentialCipher.decrypt(secret_ciphertext)
  end

  def secret=(value)
    self.secret_ciphertext = value.present? ? CredentialCipher.encrypt(value) : nil
    self.secret_last4 = value.to_s.last(4)
  end

  def masked_secret
    secret_last4.present? ? "********#{secret_last4}" : nil
  end

  private

  def connection_belongs_to_user_team
    return unless user && connection

    errors.add(:connection, :must_belong) unless user.teams.exists?(id: connection.team_id)
  end
end
