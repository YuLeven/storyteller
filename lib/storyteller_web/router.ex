defmodule StorytellerWeb.Router do
  use StorytellerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug StorytellerWeb.Locale
    plug :put_root_layout, html: {StorytellerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/auth", StorytellerWeb do
    pipe_through :browser

    get "/connect", AuthController, :connect
    post "/authorize", AuthController, :authorize
    post "/model", AuthController, :update_model
    get "/callback", AuthController, :callback
    post "/disconnect", AuthController, :disconnect
  end

  scope "/", StorytellerWeb do
    pipe_through :browser

    post "/locale", LocaleController, :update
  end

  scope "/", StorytellerWeb do
    pipe_through :browser

    get "/campaigns/:id/backup", CampaignBackupController, :show

    live_session :default, on_mount: [{StorytellerWeb.Locale, :default}] do
      live "/", CampaignLive.Index, :index
      live "/campaigns/new", CampaignLive.New, :new
      live "/campaigns/:id/edit", CampaignLive.Edit, :edit
      live "/campaigns/:id", CampaignLive.Show, :show
      live "/campaigns/:campaign_id/sessions/:session_id", SessionLive.Show, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", StorytellerWeb do
  #   pipe_through :api
  # end
end
