# frozen_string_literal: true

class CacheStrategiesController < ApplicationController
  before_action :set_project
  before_action :set_strategy, only: :update

  def index
    @strategies = @project.cache_strategies.order(:namespace)
  end

  def update
    if @strategy.update(strategy_params)
      redirect_to team_project_cache_strategies_path(@team, @project), notice: I18n.t("flash.cache_strategy_updated")
    else
      @strategies = @project.cache_strategies.order(:namespace)
      render :index, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @team = current_user.teams.find(params[:team_id])
    @project = @team.projects.find(params[:project_id])
    session[:team_id] = @team.id
  end

  def set_strategy
    @strategy = @project.cache_strategies.find(params[:id])
  end

  def strategy_params
    params.require(:cache_strategy).permit(:ttl_seconds, :stale_grace_seconds, :enabled)
  end
end
