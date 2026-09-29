# Feature log

## 2026-09-29 — In-progress implementation checkpoint

- Added atomic campaign setup for starting world details, GM-controlled characters, and typed campaign panels with public/private visibility.
- Added the session play screen with campaign-wide timeline, NPC speech and activity, world header, action composer, pending/retry states, and a player-click D20 flow.
- Added the local ChatGPT-plan OAuth and streamed Responses adapter behind fake-testable boundaries. No live account was connected in this checkpoint.
- **Checked:** focused campaign/panel checks passed for the new behavior, and the session plus campaign LiveView suite passed (11 tests, 0 failures). See `docs/CHECKPOINT_2026-09-29.md` for integration status and remaining work.

## 2026-09-29 — Campaign panel updates in the turn loop

- GM proposals can update existing typed panel fields using stable campaign keys. Unknown fields, invalid values, negative quantities/money, and unsupported formulas fail validation before any changes apply.
- Panel updates commit in the same database transaction as the turn and its audit events. Public fields appear in the play page and public timeline; GM-private panel changes stay out of player projections.
- **Checked:** the complete WSL suite passed (76 tests, 0 failures), warnings-as-errors compilation passed, and the additive panel migration ran against the persistent development database.

## 2026-09-29 — Localized interface and bounded campaign memory

- Added a persisted English/Spanish/French interface selector across the campaign library, setup, details, account connection, and session play screens. User-authored story content and the selected narration language remain campaign data.
- Added translated validation and error messages. Gettext extraction found 236 current UI strings; Spanish and French catalogs both merge with zero missing messages.
- Added separate persisted public and GM-private history summaries. Each is bounded to 6,000 characters, and each request includes at most the most recent 40 timeline events. Summary updates validate and commit with the turn; older timeline events remain in durable storage.
- **Checked:** `mix format`, `mix compile --warnings-as-errors`, and the full test suite (80 tests, 0 failures) passed. Locale behavior tests exercise translated campaign screens, content preservation, and the CSRF-protected locale selector post. Migrations 00400 and 00500 were applied additively. The local HTTP check returned 200 and displayed the fictional QA campaign. Visual/accessibility inspection and live OAuth remain outstanding.

## 2026-09-29 — Tabletop play-screen visual pass

- Shifted the campaign library and play screen toward a shared tabletop mood with a darker forest palette, warm brass accents, a framed scene area, parchment-toned narration, distinct dialogue bubbles, and a connected world-state rail.
- Kept the campaign library spacious around its single active campaign rather than leaving the card stranded on one side of the page.
- **Checked:** rebuilt assets and reviewed headless Edge screenshots of the library and fictional QA session at a 1440px capture width. Keyboard, narrow-screen, and screen-reader review are still outstanding.

## 2026-09-29 — Versioned GM policy

- Recorded the original vineyard chat's gameplay rules in `docs/GM_POLICY.md` without including its private plot or state: the GM advances time and weather, the player makes decisions and supplies rolls, and the in-world date remains visible.
- Updated the import plan to reflect read-only access to the original chat and the need to review truncated long messages before reconstructing campaign state.
- **Checked:** Compared the policy against the opening vineyard instructions and later explicit player corrections about time, date, and weather.

## 2026-09-29 — Campaign and session foundation

- Added a reviewed campaign setup with title, premise, setting, tone, narration language, and player character details.
- Added a persistent campaign list and detail page with session history, resume links, archive, and restore actions.
- Campaign creation saves the campaign and its first session together. Starting a later session closes the previous active session in the same transaction; a database index enforces one active session per campaign.
- Added a fictional QA campaign seed, separate campaign fixtures for tests, and WSL/PostgreSQL setup notes. No vineyard data is included in the QA seed or automated fixtures.
- Bound the LiveView server to `127.0.0.1:4000`, restricted development WebSocket origins to `127.0.0.1:4000` and `localhost:4000`, and disabled sensitive DB details in connection errors.
- **Checked:** `mix format` completed, the focused Campaign/LiveView suite passed (13 tests, 0 failures), and the complete suite passed (18 tests, 0 failures). Development migrations ran against `storyteller_dev`; automated tests used `storyteller_test`.

The resumed session page currently confirms stored campaign/session setup; the interactive turn screen is the next feature.

## 2026-09-29 — Persistent play and OAuth foundations

- Added campaign-scoped world and character records with separate public and GM-private facts, plus ordered turn events across multiple sessions.
- Added idempotent player actions, validated GM proposals, atomic state application, recoverable failures, and an explicit player-click D20 that records one result.
- Closing a session or archiving a campaign invalidates open turns. A generation counter prevents late GM responses from applying after retry or closure.
- Added local credential storage and OIDC validation primitives for the planned ChatGPT sign-in flow. No account was connected and no live model request was made in this slice.
- **Checked:** WSL formatting and warnings-as-errors compilation passed. The isolated `storyteller_test` database was recreated for the revised migration; the complete suite passed (44 tests, 0 failures). A separate read-only review found no remaining Play lifecycle or retry issue.
- An additive reconciliation migration installed the final lifecycle triggers and positive event-sequence constraint in the durable development database, which had applied an earlier draft of the Play migration. The existing campaign record remained present. The same migration also ran successfully against the test schema where those objects already existed.
