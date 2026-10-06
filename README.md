# Storyteller

Storyteller is a locally hosted, single-player tabletop role-playing game. You create a campaign, play a character, and talk to an AI game master. Campaigns can span multiple sessions, with the story, world details, and game state saved in a local PostgreSQL database so play can continue later.

The project is in active development. Its current focus is improving story quality and the local play experience; it is not a version 1.0 release.

## What it does

- Create campaigns with a premise, setting, player character, supporting cast, starting situation, and configurable world panels.
- Play through actions, questions, observations, time passage, and player-initiated D20 rolls.
- Keep campaign state such as character presence, places and routes, inventory, resources, and story notes alongside the session history.
- Validate proposed game-state changes before saving them, and resume a campaign in another session.
- Export and restore campaigns as JSON backups. A backup includes session history and private GM context, so keep it somewhere private.
- Use the interface in English, Spanish, or French.

The game master uses ChatGPT through the locally hosted app's OAuth connection and the Responses API. It uses your ChatGPT plan allowance, not an API key or API credits; usage limits are shared with your other ChatGPT apps. Relevant campaign context and your submitted actions are sent to ChatGPT to generate each response. Campaign records remain in the local database.

## Play a campaign

1. Start the app using the instructions below and open [http://127.0.0.1:4000](http://127.0.0.1:4000).
2. Open **Connect ChatGPT** at `/auth/connect` and authorize the account. This plan-usage preview is available only for eligible accounts and apps.
3. Choose **New campaign**, enter the story and character details, review the setup, and create the campaign. A first session is ready to resume.
4. In the session, describe what your character does, ask the GM a question, inspect the scene, or choose **Time passage** for an uninterrupted interval. Roll your own D20 when the GM calls for one.
5. Return to the campaign to resume the current session or start another. Use the campaign's backup controls to export or restore a separate copy.

The development database is seeded with fictional QA campaigns for trying the game. Create a separate campaign for your own play.

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

## Local data and configuration

- Campaigns and sessions are stored in PostgreSQL on the local development machine.
- ChatGPT OAuth credentials and the generated development cookie-signing key are stored outside the repository in `${STORYTELLER_AUTH_DIR:-$HOME/.config/storyteller}` with owner-only permissions. Set `STORYTELLER_AUTH_DIR` to use another private directory.
- The development server binds to `127.0.0.1` by default. Keep it local when using personal campaign data.
- `PORT` changes the development server port and OAuth callback port. `STORYTELLER_DB_NAME` changes the development database name. Database username, password, and socket directory can be set with `STORYTELLER_DB_USERNAME`, `STORYTELLER_DB_PASSWORD`, and `STORYTELLER_DB_SOCKET_DIR`.
- `mix test` uses the separate `storyteller_test` database; it does not use the development QA campaigns.

## Project docs

- [Local development](docs/LOCAL_DEVELOPMENT.md) — setup, database details, and ChatGPT connection notes.
- [GM policy](docs/GM_POLICY.md) — campaign-independent rules for the AI game master.
- [UX acceptance](docs/UX_ACCEPTANCE.md) — functional acceptance and current product priorities.
- [Implementation plan](IMPLEMENTATION_PLAN.md) — product scope, design decisions, and roadmap.
- [Feature log](docs/FEATURE_LOG.md) — implementation history.

Storyteller is licensed under the [MIT License](LICENSE).
