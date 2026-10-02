# Local development

Storyteller runs as a Phoenix LiveView site inside WSL 2. The browser UI binds to loopback on port 4000; it is not exposed to the local network.

## Start the app

Open Ubuntu in WSL and run:

```sh
sudo service postgresql start
cd /mnt/d/Game/storyteller
mix setup
mix phx.server
```

Open [http://127.0.0.1:4000](http://127.0.0.1:4000) in the Windows browser. `mix setup` fetches dependencies, creates and migrates the development database, seeds one separate fictional QA campaign, and builds the local CSS and JavaScript assets.

On first development startup, Storyteller generates a persistent cookie-signing key at `${STORYTELLER_AUTH_DIR:-$HOME/.config/storyteller}/dev_secret_key_base`. It is stored outside the repository with owner-only file and directory permissions, so browser sessions survive server restarts without a committed development secret. `SECRET_KEY_BASE` can override it for a local environment when needed.

The repository's supported toolchain is Elixir 1.18 with Erlang/OTP 25 or newer. The current WSL setup uses the official Elixir 1.18.4 release under `/opt/elixir-1.18.4`, with commands on `/usr/local/bin` ahead of the Windows Elixir installation.

JOSE is pinned to 1.11.10 in `mix.exs` for the current OTP 25 toolchain. JOSE 1.11.11 and 1.11.12 fail to compile here because their Erlang sources refer to the undefined `dynamic()` type. Recheck compatibility before changing or widening this pin.

## Test the GM with a ChatGPT plan

Connect a personal ChatGPT account from the local `/auth/connect` page. Storyteller uses the account's OAuth session to list supported models and stream GM responses through the Responses endpoint. This local integration does not use an API key or API billing; no usage reset is consumed by the application.

The account's ChatGPT usage allowance is shared with other ChatGPT apps and can temporarily reject requests. When that happens, check ChatGPT Usage settings, resume requests in Storyteller if the account-wide pause is shown, then explicitly retry the saved turn. A retry continues the same durable turn and any already-recorded D20 result.

Use the separate fictional **The Amber Orchard** campaign for live testing. The current QA session is `/campaigns/34/sessions/35`; do not use the Vineyard campaign as test data.

Public story events retain the campaign date/time that applied when they were recorded. A player's action can show the time before the GM advances the scene; the GM response shows the resulting time. Older events created before this metadata existed have no time label rather than a misleading UTC timestamp.

## Persistent data and tests

The development database is PostgreSQL, stored by the WSL cluster under `/var/lib/postgresql/16/main`. Stopping WSL or PostgreSQL stops the service but does not remove this database. Start the PostgreSQL service again before starting Storyteller.

The default local development connection uses the WSL `root` database role over the Unix socket, with `CREATEDB` and without superuser privileges or a password. The connection can be overridden with `STORYTELLER_DB_USERNAME`, `STORYTELLER_DB_PASSWORD`, and `STORYTELLER_DB_SOCKET_DIR`.

`mix test` uses the separate `storyteller_test` database and the SQL sandbox; it does not run development seeds. Test fixtures create only fictional QA worlds. `mix run priv/repo/seeds.exs` adds the idempotent **QA Campaign: The Quiet Observatory** to the development database for manual testing. It is separate from any future approved vineyard campaign import.
