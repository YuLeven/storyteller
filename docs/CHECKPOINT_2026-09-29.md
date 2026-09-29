# Implementation checkpoint — 2026-09-29

Storyteller is an in-progress local Phoenix LiveView TTRPG site. This checkpoint is committed to `main` so work can resume without reconstructing the current state. It is not a polished or live-provider-verified MVP.

## Implemented and checked

- Durable PostgreSQL campaigns and continuous sessions, with a separate fictional development QA campaign and a separate test database. The vineyard campaign has not been imported or used for QA.
- Atomic campaign setup with starting date, time, weather, location, optional GM-controlled characters, and typed campaign panel fields. Public panel projection filters GM-private values. Focused campaign/panel checks passed; an older session-page assertion was then updated for the new play screen.
- Public play timeline, text action composer, asynchronous GM resolution, persisted pending/failed turns, retry, attributed NPC dialogue and activity, world header, and a player-click D20 request. Focused LiveView checks passed: 11 tests, 0 failures.
- GM proposals can update known typed campaign fields. Values are validated and committed with their turn, and audit events preserve public/private visibility. Public panel fields appear on the play page.
- Persisted English, Spanish, and French interface locale selection. Gettext covers the campaign library/setup/detail pages, ChatGPT connection and error screens, the play UI, and shared chrome. Authored campaign content and narration-language choices remain unchanged when the interface locale changes.
- Persisted public and GM-private campaign summaries. The GM prompt maintains these separately, validates each at 6,000 characters, and sends only the newest 40 events alongside them, keeping long campaign context bounded while the full timeline remains stored.
- Versioned, campaign-independent GM policy in `docs/GM_POLICY.md`, based on the original vineyard game's explicit play rules. No vineyard plot or state is in the public repository.
- ChatGPT-plan OAuth and Responses adapter code using the locally hosted preview flow, protected server-side token storage, and a fake-testable HTTP boundary. Live account consent and a real Responses call have not occurred.

## Verification at the checkpoint

- The earlier focused campaign run had one obsolete session-page copy assertion; it was updated. The session and campaign LiveView suite passed 11 tests, 0 failures.
- The first OAuth/GM/controller focused run had 8 test-harness failures. Those fixtures were corrected. The latest integrated suite passes: **80 tests, 0 failures**.
- `mix format`, `mix compile --warnings-as-errors`, and Gettext extraction/merge passed. Spanish and French each have translations for all 236 extracted UI strings; merge reported no missing messages.
- Additive migrations `20260929000400` (UI locale preference) and `20260929000500` (history summaries) were applied to the durable development database without resetting it. The full suite used the separate `storyteller_test` database.
- A local HTTP smoke check returned `200 OK` and showed the locale selector and fictional QA campaign. Headless Edge screenshots of the campaign library and play screen were reviewed at a 1440px capture width. The dark forest, brass, and warm framed story-board styling improves contrast and makes the narrative scene more prominent; keyboard, narrow-screen, and screen-reader review remain outstanding. The existing local server on port `4000` was left running.
- Live OAuth consent and a real Responses request have not occurred.

## Resume in this order

1. Keep the suite green in WSL and preserve the durable dev QA campaign. Automated runs use only `storyteller_test`.
2. Perform keyboard, narrow-screen, and screen-reader review on the fictional QA campaign, including a locale switch. Do not use the vineyard campaign for testing.
3. After the local flow is reviewable, connect the owner's ChatGPT account through `/auth/connect` and run one opt-in streamed Responses smoke check. Confirm eligibility; do not use API keys or purchased credits.
4. Keep GM-controlled dice as future work unless the campaign rules call for them; the current source-derived policy makes the player the roller. Review the full vineyard history for an owner-approved import. Long retrieved messages can be truncated, so do not infer missing facts or alter the original chat.

## Local development notes

- Run Elixir, Mix, and Phoenix from WSL Ubuntu in `/mnt/d/Game/storyteller`. PostgreSQL runs persistently in WSL; setup details are in `docs/LOCAL_DEVELOPMENT.md`.
- JOSE is pinned to 1.11.10 because 1.11.11 and 1.11.12 use an Erlang type unsupported by the installed OTP 25. The package's 1.11.8 changelog explicitly records OTP 24/25 support, and 1.11.10 compiles on this machine.
- The OAuth credential file is outside Git, under the WSL user's `~/.config/storyteller`, with restricted file permissions. Keep it and any vineyard export out of this public repository.
- GitHub SSH authentication works from WSL. The configured remote may still be HTTPS; push via `git@github.com:YuLeven/storyteller.git` or switch the remote to SSH when resuming.
