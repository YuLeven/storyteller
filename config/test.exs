import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :storyteller, Storyteller.Repo,
  username: System.get_env("STORYTELLER_DB_USERNAME", System.get_env("USER", "root")),
  password: System.get_env("STORYTELLER_DB_PASSWORD"),
  socket_dir: System.get_env("STORYTELLER_DB_SOCKET_DIR", "/var/run/postgresql"),
  database: "storyteller_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :storyteller, StorytellerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "bQaekVCE83c9ZchS7y/gsxZOAs2ON1jj5QWY/bEwvzLJelsGjQzB49ZlGTap9BgN",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
