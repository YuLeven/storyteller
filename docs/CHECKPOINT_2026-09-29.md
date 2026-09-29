# Implementation checkpoint — 2026-09-29

Storyteller is an in-progress local Phoenix LiveView TTRPG site. This checkpoint is committed to `main` so work can resume without reconstructing the current state. It is not a polished or live-provider-verified MVP.

## Implemented and checked

- Durable PostgreSQL campaigns and continuous sessions, with a separate fictional development QA campaign and a separate test database. The vineyard campaign has not been imported or used for QA.
- Atomic campaign setup with starting date, time, weather, location, optional GM-controlled characters, and typed campaign panel fields. Public panel projection filters GM-private values. Focused campaign/panel checks passed; an older session-page assertion was then updated for the new play screen.
- Public play timeline, text action composer, asynchronous GM resolution, persisted pending/failed turns, retry, attributed NPC dialogue and activity, world header, and a player-click D20 request. Focused LiveView checks passed: 11 tests, 0 failures.
- GM proposals can update known typed campaign fields. Values are validated and committed with their turn, and audit events preserve public/private visibility. Public panel fields appear on the play page.
- Versioned, campaign-independent GM policy in `docs/GM_POLICY.md`, based on the original vineyard game's explicit play rules. No vineyard plot or state is in the public repository.
- ChatGPT-plan OAuth and Responses adapter code using the locally hosted preview flow, protected server-side token storage, and a fake-testable HTTP boundary. Live account consent and a real Responses call have not occurred.

## Verification at the checkpoint

- The earlier focused campaign run had one obsolete session-page copy assertion; it was updated. The session and campaign LiveView suite passed 11 tests, 0 failures.
- The first OAuth/GM/controller focused run had 8 test-harness failures. Those fixtures were corrected; the complete integrated suite now passes: **76 tests, 0 failures**.
- `mix compile --warnings-as-errors` passed, and migration `20260929000300` was applied to the durable development database. The full suite used the separate `storyteller_test` database.
- Live OAuth consent, a real Responses request, and a visual browser review remain unverified.

## Resume in this order

1. Keep the suite green in WSL and preserve the durable dev QA campaign. Automated runs use only `storyteller_test`.
2. Implement persisted UI locale selection and translate all interface flows into English, Spanish, and French. Keep narration language and existing story text unchanged when changing the UI locale.
3. Add the separate audited GM-controlled roll path and bounded long-campaign context with an older-history summary. Run visual and accessibility review on the fictional QA campaign.
4. After the local flow is reviewable, connect the owner's ChatGPT account through `/auth/connect` and run one opt-in streamed Responses smoke check. Confirm eligibility; do not use API keys or purchased credits.
5. Review the full vineyard history for an owner-approved import. Conversation history is available read-only, but long retrieved messages can be truncated. Do not infer missing facts or alter the original chat.

## Local development notes

- Run Elixir, Mix, and Phoenix from WSL Ubuntu in `/mnt/d/Game/storyteller`. PostgreSQL runs persistently in WSL; setup details are in `docs/LOCAL_DEVELOPMENT.md`.
- JOSE is pinned to 1.11.10 because 1.11.11 and 1.11.12 use an Erlang type unsupported by the installed OTP 25. The package's 1.11.8 changelog explicitly records OTP 24/25 support, and 1.11.10 compiles on this machine.
- The OAuth credential file is outside Git, under the WSL user's `~/.config/storyteller`, with restricted file permissions. Keep it and any vineyard export out of this public repository.
- GitHub SSH authentication works from WSL. The configured remote may still be HTTPS; push via `git@github.com:YuLeven/storyteller.git` or switch the remote to SSH when resuming.
