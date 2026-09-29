# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :storyteller,
  ecto_repos: [Storyteller.Repo],
  generators: [timestamp_type: :utc_datetime]

auth_store_dir =
  System.get_env("STORYTELLER_AUTH_DIR") ||
    Path.join(System.user_home!(), ".config/storyteller")

config :storyteller, Storyteller.Auth.TokenStore,
  path: Path.join(auth_store_dir, "chatgpt_credentials.json")

config :storyteller, Storyteller.Auth.OAuth,
  app_name: "Storyteller",
  callback_uri: "http://127.0.0.1:4000/auth/callback"

# Configures the endpoint
config :storyteller, StorytellerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: StorytellerWeb.ErrorHTML, json: StorytellerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Storyteller.PubSub,
  live_view: [signing_salt: "Hh5KYqUA"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  storyteller: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  storyteller: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
