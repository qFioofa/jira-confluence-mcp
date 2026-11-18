# frozen_string_literal: true

class ProjectsController < ApplicationController
  before_action :set_team
  before_action :set_project, only: %i[show edit update]
  before_action(only: %i[new create edit update]) { require_team_admin!(@team) }

  def index
    @projects = @team.projects.order(:name)
  end

  def show
    @presets = @project.presets.order(:kind, :key)
    @endpoints = current_user.mcp_endpoints.active.where(project: @project)
    @cache_hits = CacheEvent.where(project: @project, hit: true).sum(:count)
    @cache_misses = CacheEvent.where(project: @project, hit: false).sum(:count)
    @cache_hit_rate = (@cache_hits + @cache_misses).positive? ?
      ((@cache_hits.to_f / (@cache_hits + @cache_misses)) * 100).round(1) : 0
    @recent_calls = ToolCall.where(project: @project).order(created_at: :desc).limit(15)
  end

  def new
    @project = @team.projects.new
  end

  def create
    @project = @team.projects.new(project_params)
    if @project.save
      audit!("project.create", target: @project, team: @team, metadata: { slug: @project.slug })
      redirect_to team_project_path(@team, @project), notice: I18n.t("flash.project_created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @project.update(project_params)
      audit!("project.update", target: @project, team: @team, metadata: { slug: @project.slug })
      redirect_to team_project_path(@team, @project), notice: I18n.t("flash.project_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_team
    @team = current_user.teams.find(params[:team_id])
    session[:team_id] = @team.id
  end

  def set_project
    @project = @team.projects.find(params[:id])
  end

  def project_params
    attrs = params.require(:project).permit(
      :name, :slug, :jira_connection_id, :confluence_connection_id, :style,
      :jira_keys, :spaces
    )
    attrs[:jira_keys] = split_list(attrs[:jira_keys]) if attrs.key?(:jira_keys)
    attrs[:spaces] = split_list(attrs[:spaces]) if attrs.key?(:spaces)
    attrs
  end

  def split_list(value)
    value.to_s.split(",").map(&:strip).reject(&:empty?)
  end
end
