# frozen_string_literal: true

class RemoveOauthFieldsFromUserCredentials < ActiveRecord::Migration[8.1]
  def change
    remove_index :user_credentials, %i[user_id cloud_id]
    remove_column :user_credentials, :refresh_ciphertext, :text
    remove_column :user_credentials, :cloud_id, :string
    remove_column :user_credentials, :oauth_scope, :string
    remove_column :user_credentials, :expires_at, :datetime
  end
end
