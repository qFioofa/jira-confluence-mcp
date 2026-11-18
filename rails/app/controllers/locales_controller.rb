# frozen_string_literal: true

class LocalesController < ApplicationController
  skip_before_action :require_login

  def update
    locale = params[:locale].to_s
    session[:locale] = locale if I18n.available_locales.map(&:to_s).include?(locale)
    redirect_back fallback_location: root_path
  end
end
