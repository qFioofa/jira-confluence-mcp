# frozen_string_literal: true

class CachesController < ApplicationController
  before_action :set_project

  def clear
    connections = [@project.jira_connection, @project.confluence_connection].compact
    store = JiraCache::RailsStore.new(
      cache: Rails.cache,
      user: current_user,
      project: @project,
      connections: connections,
      resolver: JiraCache::StrategyResolver.new(project: @project, user: current_user, connections: connections),
      logger: StructuredLogger.new(Rails.logger)
    )
    store.clear(ns: params[:namespace].presence)
    audit!("cache.clear", target: @project, team: @team,
           metadata: { namespace: params[:namespace].presence })
    redirect_to team_project_path(@team, @project), notice: I18n.t("flash.cache_invalidated")
  end

  private

  def set_project
    @team = current_user.teams.find(params[:team_id])
    @project = @team.projects.find(params[:project_id])
    session[:team_id] = @team.id
  end
end
