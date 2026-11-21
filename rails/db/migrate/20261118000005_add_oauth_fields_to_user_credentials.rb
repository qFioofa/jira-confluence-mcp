# frozen_string_literal: true

class AddOauthFieldsToUserCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :user_credentials, :refresh_ciphertext, :text
    add_column :user_credentials, :cloud_id, :string
    add_column :user_credentials, :oauth_scope, :string
    add_index :user_credentials, %i[user_id cloud_id]
  end
end
