# Contributing

Thanks for helping improve Storyteller. Work toward a fun, engaging, quick-paced, consistent, lifelike campaign. Protect player agency and established canon; do not weaken validation to make a test pass.

## Development setup

Use Ubuntu on WSL 2 with Elixir 1.18, Erlang/OTP 25 or newer, and PostgreSQL. Follow [Local development](docs/LOCAL_DEVELOPMENT.md) to install dependencies and start the app. Run Elixir commands inside WSL from the repository directory.

## Checks

Before submitting a change, run the relevant behavioral tests and these project checks:

```sh
mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix test
```

`mix test` uses the separate `storyteller_test` database. Tests should use deterministic fake providers and independently authored fictional data. Prefer behavioral tests that prove what a player or campaign author can observe over tests tied to internal function structure. For gameplay changes, cover successful state changes, rejected or repaired proposals, persistence, and player-facing failure behavior as applicable.

Do not include credentials, tokens, account details, personal campaign exports, or private player data in commits, fixtures, logs, or issue reports. Never copy campaign material from a player's private conversation into a test fixture. Focused live-provider checks require an explicitly authorized task, a small number of purposeful turns, and fictional campaign data; a fake-provider test is not evidence of live model behavior.

## Pull requests and issues

Describe the player-visible problem and intended result, list the behavioral checks run, and call out remaining limitations. Keep changes focused. Report model behavior with the chosen model and reasoning setting only when known; do not claim performance or story-quality improvements from a single unrepresentative sample.
