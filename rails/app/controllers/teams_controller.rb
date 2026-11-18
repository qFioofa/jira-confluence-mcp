# frozen_string_literal: true

class TeamsController < ApplicationController
  def index
    @teams = current_user.teams.order(:name)
  end

  def show
    @team = current_user.teams.find(params[:id])
    session[:team_id] = @team.id
    @projects = @team.projects.order(:name)
    @connections = @team.connections.order(:provider, :name)
  end

  def new
    @team = Team.new
  end

  def create
    @team = Team.new(team_params)
    @team.transaction do
      @team.save!
      @team.memberships.create!(user: current_user, role: "admin")
    end
    session[:team_id] = @team.id
    redirect_to @team, notice: I18n.t("flash.team_created")
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private

  def team_params
    params.require(:team).permit(:slug, :name)
  end
end
