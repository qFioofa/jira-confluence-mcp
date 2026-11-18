# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    set_current_context
    @teams = current_user.teams.order(:name)
    @team = current_team
    @projects = @team ? @team.projects.order(:name) : Project.none
    @connections = @team ? @team.connections.order(:provider, :name) : Connection.none
    @endpoints = current_user.mcp_endpoints.active.includes(:project).order(created_at: :desc).limit(10)
    @audit_events = @team ? AuditEvent.where(team: @team).order(created_at: :desc).limit(10) : AuditEvent.none
  end
end
