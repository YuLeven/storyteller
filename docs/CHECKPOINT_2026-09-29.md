# Implementation checkpoint — 2026-09-29

Storyteller is an in-progress local Phoenix LiveView TTRPG site. This checkpoint is committed to `main` so work can resume without reconstructing the current state. It is not a polished or live-provider-verified MVP.

## Implemented and checked

- Durable PostgreSQL campaigns and continuous sessions, with a separate fictional development QA campaign and a separate test database. The vineyard campaign has not been imported or used for QA.
- Atomic campaign setup with starting date, time, weather, location, optional GM-controlled characters, and typed campaign panel fields. Public panel projection filters GM-private values. Focused campaign/panel checks passed; an older session-page assertion was then updated for the new play screen.
- Public play timeline, text action composer, asynchronous GM resolution, persisted pending/failed turns, retry, attributed NPC dialogue and activity, world header, and a player-click D20 request. Focused LiveView checks passed: 11 tests, 0 failures.
- Versioned, campaign-independent GM policy in `docs/GM_POLICY.md`, based on the original vineyard game's explicit play rules. No vineyard plot or state is in the public repository.
- ChatGPT-plan OAuth and Responses adapter code using the locally hosted preview flow, protected server-side token storage, and a fake-testable HTTP boundary. Live account consent and a real Responses call have not occurred.

## Verification at the checkpoint

- Campaign and panel focused run: 19 of 20 tests passed; its sole failure was an old session-page copy assertion. That assertion was updated in the play-screen slice, whose subsequent focused LiveView run passed 11 tests, 0 failures.
- OAuth/GM/controller focused run: 33 tests, 8 failures. The agent identified test harness issues: a nested fake OIDC module resolves incorrectly, a fake GM request expects map options where the adapter passes a keyword list, and one controller test uses a deprecated flash assertion. These fixes and a rerun are the first pickup task.
- The complete integrated suite and live OAuth smoke check were not run before this checkpoint.

## Resume in this order

1. Run WSL formatting, warnings-as-errors compilation, development migration, and the complete test suite. Resolve any integration failures before starting new features. Keep `storyteller_dev` and its QA campaign; never reset it to fix tests. Use the separate `storyteller_test` database for automated tests.
2. Review the OAuth fake-test results, connect the owner's ChatGPT account through the local `/auth/connect` page, and run one opt-in streamed Responses smoke check. Confirm the account and app are eligible for ChatGPT-plan usage. Do not use an API key or purchased API credits.
3. Integrate typed panel changes into GM proposal validation, the atomic turn commit, model context, and the play screen. Preserve an event for every visible value change and exclude private fields from public events.
4. Implement persisted UI locale selection and translate the whole interface into English, Spanish, and French. Keep narration language and existing story text unchanged when switching UI locale.
5. Add the separate audited GM-controlled roll path and bounded long-campaign context with an older-history summary. Continue behavioral tests and visual/accessibility review on the fictional QA campaign.
6. Review the full vineyard history for an owner-approved import. Conversation history is available read-only, but long retrieved messages can be truncated. Do not infer missing facts or alter the original chat.

## Local development notes

- Run Elixir, Mix, and Phoenix from WSL Ubuntu in `/mnt/d/Game/storyteller`. PostgreSQL runs persistently in WSL; setup details are in `docs/LOCAL_DEVELOPMENT.md`.
- JOSE is pinned to 1.11.10 because 1.11.11 and 1.11.12 use an Erlang type unsupported by the installed OTP 25. The package's 1.11.8 changelog explicitly records OTP 24/25 support, and 1.11.10 compiles on this machine.
- The OAuth credential file is outside Git, under the WSL user's `~/.config/storyteller`, with restricted file permissions. Keep it and any vineyard export out of this public repository.
- GitHub SSH authentication works from WSL. The configured remote may still be HTTPS; push via `git@github.com:YuLeven/storyteller.git` or switch the remote to SSH when resuming.
