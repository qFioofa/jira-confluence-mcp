# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :require_login

  rate_limit to: 10, within: 1.minute, only: :create,
             with: -> { redirect_to login_path, alert: I18n.t("flash.too_many_attempts") },
             store: Rails.cache,
             name: "login"

  def new
    redirect_to root_path if current_user
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user&.authenticate(params[:password])
      locale = session[:locale]
      reset_session
      session[:locale] = locale if locale.present?
      session[:user_id] = user.id
      session[:team_id] = user.teams.order(:name).first&.id
      redirect_to root_path, notice: I18n.t("flash.signed_in")
    else
      flash.now[:alert] = I18n.t("sessions.invalid")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    locale = session[:locale]
    reset_session
    session[:locale] = locale if locale.present?
    redirect_to login_path, notice: I18n.t("flash.signed_out")
  end
end
