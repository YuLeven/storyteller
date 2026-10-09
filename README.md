# Storyteller

Storyteller is a locally hosted, single-player tabletop role-playing game. You create a campaign, play a character, and talk to an AI game master. Campaigns can span multiple sessions, with the story, world details, and game state saved in a local PostgreSQL database so play can continue later.

The project is in active development. Its current focus is compelling, reliable campaign play; see the [product acceptance criteria](docs/UX_ACCEPTANCE.md) and [implementation plan](IMPLEMENTATION_PLAN.md) for current priorities.

## What it does

- Create campaigns with a premise, setting, player character, supporting cast, starting situation, and configurable world panels.
- Play through actions, questions, observations, time passage, and player-initiated D20 rolls.
- Keep campaign state such as character presence, places and routes, inventory, resources, and story notes alongside the session history.
- Validate proposed game-state changes before saving them, and resume a campaign in another session.
- Export and restore campaigns as JSON backups. A backup includes session history and private GM context, so keep it somewhere private.
- Use the interface in English, Spanish, French, or Italian.

The game master uses ChatGPT through the locally hosted app's OAuth connection and the Responses API. It uses your ChatGPT plan allowance, not an API key or API credits; usage limits are shared with your other ChatGPT apps. Relevant campaign context and your submitted actions are sent to ChatGPT to generate each response. Campaign records remain in the local database.

## Connect ChatGPT and play

Storyteller is a local web app that connects to ChatGPT with your account's authorization; there is no separate plugin to install in a custom GPT.

1. Start the app using the instructions below and open [http://127.0.0.1:4000](http://127.0.0.1:4000).
2. Open **Connect ChatGPT** at [http://127.0.0.1:4000/auth/connect](http://127.0.0.1:4000/auth/connect), choose **Continue with ChatGPT**, and review and approve access in ChatGPT. You will return to the local app when authorization completes. This plan-usage preview is available only for eligible accounts and apps.
3. On the same page, optionally choose an available model under **Game master model**. **Automatic** uses the first model available to the connected account.
4. Choose **New campaign**, enter and review the campaign details, and create it. Open the campaign and resume its first session; Storyteller prepares the opening scene automatically.
5. In the session, describe what your character does, ask the GM a question, inspect the scene, or choose **Time passage** for an uninterrupted interval. Roll your own D20 when the GM calls for one.
6. Return to the campaign to resume the current session or start another. Starting another session completes the active one while keeping its history. Use the campaign's backup controls to export or restore a separate copy.

The development database is seeded with fictional QA campaigns for trying the game. Their settings and characters are examples; create a separate campaign with your own world and cast for your play.

### Example: start a campaign at your own finca

The campaign wizard lets you define the setting, premise, player character, opening location, date, weather, inventory, and optional campaign panels. For example, you could enter:

- **Title:** Finca La Quebrada
- **Premise:** A late frost threatens the coming harvest at a small family-run finca in Mendoza. I play its newly returned vineyard manager, who must balance the vines' needs with the people who depend on the estate.
- **Setting:** A working vineyard and winery in Mendoza, Argentina.
- **Tone:** Grounded, warm, and character-driven.
- **Player character:** Lucía Ferreyra, the vineyard manager; replace this name and role with your own character.
- **Opening location:** The lower vineyard at dawn.

Use any names, region, crop, family, staff, or starting problem you like. You do not need to reuse the sample QA campaign or its characters. After the opening scene appears, a first action could be:

> I walk through the lower vineyard to inspect how the vines handled last night's rain. Describe what I can observe and who is already there; I'll decide what to do next.

## Run locally

The supported local development setup is Ubuntu on WSL 2, with Elixir 1.18 and Erlang/OTP 25 or newer, plus PostgreSQL. Run these commands in the repository directory from a WSL shell:

```sh
sudo service postgresql start
mix setup
mix phx.server
```

`mix setup` fetches dependencies, creates and migrates the development database, inserts the fictional QA campaigns, and builds the CSS and JavaScript assets. The server listens on loopback at port 4000 by default. Open [http://127.0.0.1:4000](http://127.0.0.1:4000) in your browser.

If you need to clone the repository first:

```sh
git clone https://github.com/YuLeven/storyteller.git
cd storyteller
```

For the isolated manual-QA database, database connection options, and additional local setup details, see [Local development](docs/LOCAL_DEVELOPMENT.md).

## Run with Docker

Docker Compose builds the production release, starts a PostgreSQL database, applies database migrations, and starts Storyteller on port 4000. The app listens on `0.0.0.0` inside the container, and Compose publishes port 4000 on all host interfaces.

1. Copy the Docker environment template and generate two random hexadecimal secrets:

   ```sh
   cp .env.docker.example .env
   openssl rand -hex 32
   openssl rand -hex 64
   ```

   Put the first value in `.env` as `POSTGRES_PASSWORD` and the second as `SECRET_KEY_BASE`. Keep `.env` private; it is ignored by Git.

2. Build and start the containers from the repository directory:

   ```sh
   docker compose up --build -d
   ```

3. Open [http://127.0.0.1:4000](http://127.0.0.1:4000). Connect ChatGPT and play as described above. Use the loopback URL when completing ChatGPT authorization.

The PostgreSQL database and ChatGPT credentials are stored in Docker named volumes and survive container rebuilds and `docker compose down`. To stop Storyteller, run `docker compose down`; avoid `docker compose down -v` unless you intend to delete the campaign database and saved ChatGPT credentials. View startup logs with `docker compose logs -f storyteller`.

## Local data and configuration

- Campaigns and sessions are stored in PostgreSQL on the local development machine.
- ChatGPT OAuth credentials and the generated development cookie-signing key are stored outside the repository in `${STORYTELLER_AUTH_DIR:-$HOME/.config/storyteller}` with owner-only permissions. Set `STORYTELLER_AUTH_DIR` to use another private directory.
- The development server binds to `127.0.0.1` by default. Keep it local when using personal campaign data.
- The Docker setup stores PostgreSQL data and ChatGPT OAuth credentials in persistent named volumes and requires a stable `SECRET_KEY_BASE` in `.env`.
- `PORT` changes the development server port and OAuth callback port. `STORYTELLER_DB_NAME` changes the development database name. Database username, password, and socket directory can be set with `STORYTELLER_DB_USERNAME`, `STORYTELLER_DB_PASSWORD`, and `STORYTELLER_DB_SOCKET_DIR`.
- `mix test` uses the separate `storyteller_test` database; it does not use the development QA campaigns.

## Project docs

- [Local development](docs/LOCAL_DEVELOPMENT.md) — setup, database details, and ChatGPT connection notes.
- [GM policy](docs/GM_POLICY.md) — campaign-independent rules for the AI game master.
- [UX acceptance](docs/UX_ACCEPTANCE.md) — functional acceptance and current product priorities.
- [Implementation plan](IMPLEMENTATION_PLAN.md) — product scope, design decisions, and roadmap.
- [Feature log](docs/FEATURE_LOG.md) — implementation history.
- [Contributing](CONTRIBUTING.md) — local setup, checks, and contribution expectations.
- [Security](SECURITY.md) — local data handling and vulnerability reporting.

Storyteller is licensed under the [MIT License](LICENSE).
