# frozen_string_literal: true

class McpEndpointsController < ApplicationController
  def index
    @endpoints = current_user.mcp_endpoints.includes(:project).order(created_at: :desc)
    @projects = accessible_projects
  end

  def create
    project = accessible_projects.find(params[:project_id])
    endpoint = McpEndpoint.issue!(user: current_user, project: project, name: params[:name].presence || project.name)
    audit!("mcp_endpoint.create", target: endpoint, team: project.team, metadata: { project_id: project.id })
    flash[:mcp_token] = endpoint.token
    redirect_to mcp_endpoints_path, notice: I18n.t("flash.endpoint_created")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to mcp_endpoints_path, alert: e.message
  end

  def destroy
    endpoint = current_user.mcp_endpoints.find(params[:id])
    endpoint.revoke!
    audit!("mcp_endpoint.revoke", target: endpoint, team: endpoint.project.team, metadata: { project_id: endpoint.project_id })
    redirect_to mcp_endpoints_path, notice: I18n.t("flash.endpoint_revoked")
  end

  private

  def accessible_projects
    Project.joins(team: :memberships).where(memberships: { user_id: current_user.id }).order(:name)
  end
end
