# frozen_string_literal: true

class ApplicationController < ActionController::Base
  helper_method :current_user, :current_team, :current_locale

  around_action :switch_locale
  before_action :require_login

  private

  def switch_locale(&action)
    I18n.with_locale(locale_from_session, &action)
  end

  def locale_from_session
    requested = session[:locale].to_s
    I18n.available_locales.map(&:to_s).include?(requested) ? requested : I18n.default_locale
  end

  def current_locale
    I18n.locale
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  def current_team
    return @current_team if defined?(@current_team)

    @current_team = current_user&.teams&.find_by(id: session[:team_id]) ||
                    current_user&.teams&.order(:name)&.first
  end

  def require_login
    return if current_user

    redirect_to login_path, alert: I18n.t("flash.sign_in_required")
  end

  def require_team_admin!(team = current_team)
    return if current_user&.admin_of?(team) || current_user&.admin?

    redirect_to root_path, alert: I18n.t("flash.admin_only")
  end

  def set_current_context
    Current.user = current_user
    Current.team = current_team
  end

  def audit!(action, target: nil, team: current_team, metadata: {})
    AuditEvent.create!(
      actor: current_user,
      team: team,
      action: action,
      target_type: target&.class&.name,
      target_id: target&.id,
      metadata: metadata,
      created_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("audit event failed: #{e.class}: #{e.message}")
  end
end
