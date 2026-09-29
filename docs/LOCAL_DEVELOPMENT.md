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

The repository's supported toolchain is Elixir 1.18 with Erlang/OTP 25 or newer. The current WSL setup uses the official Elixir 1.18.4 release under `/opt/elixir-1.18.4`, with commands on `/usr/local/bin` ahead of the Windows Elixir installation.

JOSE is pinned to 1.11.10 in `mix.exs` for the current OTP 25 toolchain. JOSE 1.11.11 and 1.11.12 fail to compile here because their Erlang sources refer to the undefined `dynamic()` type. Recheck compatibility before changing or widening this pin.

## Persistent data and tests

The development database is PostgreSQL, stored by the WSL cluster under `/var/lib/postgresql/16/main`. Stopping WSL or PostgreSQL stops the service but does not remove this database. Start the PostgreSQL service again before starting Storyteller.

The default local development connection uses the WSL `root` database role over the Unix socket, with `CREATEDB` and without superuser privileges or a password. The connection can be overridden with `STORYTELLER_DB_USERNAME`, `STORYTELLER_DB_PASSWORD`, and `STORYTELLER_DB_SOCKET_DIR`.

`mix test` uses the separate `storyteller_test` database and the SQL sandbox; it does not run development seeds. Test fixtures create only fictional QA worlds. `mix run priv/repo/seeds.exs` adds the idempotent **QA Campaign: The Quiet Observatory** to the development database for manual testing. It is separate from any future approved vineyard campaign import.
