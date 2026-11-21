# frozen_string_literal: true

class UserCredentialsController < ApplicationController
  before_action :set_credential, only: %i[edit update destroy]

  def index
    @credentials = current_user.user_credentials.includes(:connection).order(created_at: :desc)
  end

  def new
    @credential = current_user.user_credentials.new
  end

  def create
    @credential = current_user.user_credentials.new(credential_params)
    if @credential.save
      audit!("credential.create", target: @credential, team: @credential.connection.team,
             metadata: { connection_id: @credential.connection_id, auth_type: @credential.auth_type })
      redirect_to user_credentials_path, notice: I18n.t("flash.credential_saved")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @credential.update(credential_params)
      audit!("credential.update", target: @credential, team: @credential.connection.team,
             metadata: { connection_id: @credential.connection_id, auth_type: @credential.auth_type })
      redirect_to user_credentials_path, notice: I18n.t("flash.credential_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def verify
    @credential = current_user.user_credentials.find(params[:id])
    result = CredentialVerifier.new(@credential).call
    audit!("credential.verify", target: @credential, team: @credential.connection.team,
           metadata: { ok: result.ok?, connection_id: @credential.connection_id })
    if result.ok?
      redirect_to user_credentials_path, notice: I18n.t("flash.credential_verified", message: result.message)
    else
      redirect_to user_credentials_path, alert: I18n.t("flash.credential_check_failed", message: result.message)
    end
  end

  def destroy
    team = @credential.connection.team
    connection_id = @credential.connection_id
    @credential.destroy!
    audit!("credential.destroy", team: team, metadata: { connection_id: connection_id })
    redirect_to user_credentials_path, notice: I18n.t("flash.credential_removed")
  end

  private

  def set_credential
    @credential = current_user.user_credentials.find(params[:id])
  end

  def credential_params
    params.require(:user_credential).permit(:connection_id, :auth_type, :email, :secret)
  end
end
