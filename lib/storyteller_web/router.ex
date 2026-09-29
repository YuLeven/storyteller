defmodule StorytellerWeb.Router do
  use StorytellerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {StorytellerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", StorytellerWeb do
    pipe_through :browser

    live "/", CampaignLive.Index, :index
    live "/campaigns/new", CampaignLive.New, :new
    live "/campaigns/:id", CampaignLive.Show, :show
    live "/campaigns/:campaign_id/sessions/:session_id", SessionLive.Show, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", StorytellerWeb do
  #   pipe_through :api
  # end
end
