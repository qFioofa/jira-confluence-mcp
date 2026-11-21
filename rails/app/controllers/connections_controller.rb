# frozen_string_literal: true

class ConnectionsController < ApplicationController
  before_action :set_team
  before_action :set_connection, only: %i[edit update]
  before_action(only: %i[new create edit update]) { require_team_admin!(@team) }

  def index
    @connections = @team.connections.order(:provider, :name)
  end

  def new
    @connection = @team.connections.new(deployment: "cloud")
  end

  def create
    @connection = @team.connections.new(connection_params)
    if @connection.save
      audit!("connection.create", target: @connection, team: @team,
             metadata: { provider: @connection.provider, base_url: @connection.base_url })
      redirect_to team_connections_path(@team), notice: I18n.t("flash.connection_created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @connection.update(connection_params)
      audit!("connection.update", target: @connection, team: @team,
             metadata: { provider: @connection.provider, base_url: @connection.base_url })
      redirect_to team_connections_path(@team), notice: I18n.t("flash.connection_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_team
    @team = current_user.teams.find(params[:team_id])
    session[:team_id] = @team.id
  end

  def set_connection
    @connection = @team.connections.find(params[:id])
  end

  def connection_params
    params.require(:connection).permit(:provider, :name, :base_url, :deployment)
  end
end
