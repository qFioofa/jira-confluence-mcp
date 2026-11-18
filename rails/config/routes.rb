# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resource :session, only: %i[new create destroy]
  get "login", to: "sessions#new", as: :login
  delete "logout", to: "sessions#destroy", as: :logout

  resources :teams, only: %i[index show new create] do
    resources :connections, only: %i[index new create edit update]
    resources :projects, only: %i[index new create show edit update] do
      resources :cache_strategies, only: %i[index update]
      post "cache/clear", to: "caches#clear", as: :clear_cache
    end
  end

  resources :user_credentials, only: %i[index new create edit update destroy] do
    post :verify, on: :member
  end

  get "locale/:locale", to: "locales#update", as: :set_locale, constraints: { locale: /en|ru/ }

  resources :mcp_endpoints, only: %i[index create destroy]

  match "/mcp/:token", to: "mcp#handle", via: :all

  root "dashboard#index"
end
