# Feature log

## 2026-09-30 — Campaign objectives and story commitments

- Added an optional campaign-scoped objective ledger with stable IDs, open/completed/abandoned status, public or GM-private visibility, and no delete path. Objectives remain canonical when a new session starts.
- GM context now includes the public and private objective lists, and policy discourages completing goals without established evidence. The provider can propose ordered, reasoned create/update operations; validation checks each operation against current and prior proposed state, rejects duplicate or unknown IDs, and applies valid batches atomically with the turn.
- Objective audit events retain full snapshots and reasons in private history. Public projections and timeline events contain only public objective snapshots, while the play board groups public objectives by status and provides Spanish/French UI labels.
- **Checked:** focused Play and locale LiveView suites pass (27 tests, 0 failures), and the full suite passes (120 tests, 0 failures). Behavioral tests cover ordered create/update snapshots, status progression across sessions, private context versus public projection/history, invalid ordering, duplicate IDs, and all-or-nothing rollback. `mix format --check-formatted`, `mix compile --warnings-as-errors`, and `mix assets.build` pass. Migration `20260930000700` was applied to the persistent development database through WSL `mix ecto.migrate`.

## 2026-09-30 — Partial inventory transfers and proposal recovery

- Added quantity-aware transfers: a partial stack keeps its existing stable ID and remainder, while the moved quantity becomes a new stack with copied properties and visibility. Whole-stack transfer event shape remains compatible.
- GM instructions now explain split identity and conservation. Invalid inventory proposals map to the normal `invalid_response` recovery state instead of being mislabeled as provider failures.
- **Checked:** domain and end-to-end behavior tests cover valid split ownership, properties, quantity conservation, stack limits, public audit payloads, and all-or-nothing rejection when a later operation over-consumes the remainder. `mix test` passed (117 tests, 0 failures).

## 2026-09-30 — Canonical places and character presence

- Added durable, campaign-scoped place records with stable IDs, descriptions, flexible surroundings, and public or GM-private visibility. A campaign's starting location becomes the player's initial place; explicitly visible character locations seed known NPC presence.
- GM prompts now receive the public and hidden place lists plus each character's canonical current place. Location changes must create a place before moving someone, use a known character and destination, and keep the player out of GM-private places.
- Accepted place creation and movement apply in the same transaction as the turn. Public projections and timeline events omit private places and private character locations. Generic world changes can no longer teleport a character or overwrite the canonical location.
- Added a player-board scene card for the current place, surroundings, and people there; character cards show a known location, and public travel events appear in the story timeline.
- Added a second idempotent fictional QA seed, **The Amber Orchard**, configured with an orchard starting scene, an NPC at a separate known place, flexible stock panels, and player-owned equipment. The earlier Observatory QA campaign is left untouched.
- **Checked:** behavior tests cover seeded player/NPC locations, public movement, private vault isolation from projection and history, rejected free-form teleportation, and continuity into another session. The full WSL suite passed (110 tests, 0 failures); Spanish and French play-board labels render in locale tests.

## 2026-09-30 — Campaign inventory and continuity

- Added optional starting items to the reviewed campaign setup, with a name, quantity, unit, category, and description. Items begin in the player's public inventory; the item structure also supports stable IDs, campaign-defined JSON properties, party/NPC ownership, and GM-private visibility.
- Added explicit GM-proposed add, whole- or partial-stack transfer, and consume operations. Validation rejects unknown items/owners, duplicate IDs, malformed properties, and over-consumption. Inventory mutations apply atomically with the turn and append visibility-scoped timeline events; general world changes cannot overwrite the inventory ledger.
- Added canonical public/GM-private inventory to each GM prompt and a player-facing board for known items. Public projections and public events omit hidden items and internal operation reasons. Campaign panels remain the place for fungible balances such as vineyard cash and stock quantities.
- **Checked:** starting inventory campaign-setup tests, inventory domain tests, and end-to-end play tests cover public/private visibility, item ownership, consumption, invalid mutations, narration without an accepted inventory operation, and continuity into another session. Full-suite and UI build checks are recorded in `docs/CHECKPOINT_2026-09-30.md`.

## 2026-09-29 — Product priorities: player board, inventory, and continuity

- Rebalanced the product plan around useful play, not appearance alone: the player should see where they are, what is happening, and what their character owns or controls.
- Added a campaign-flexible inventory and resource direction for distinct dungeon items as well as vineyard cash, wine, and vine stock. Required changes must be canonical, validated, accepted once, and traceable to campaign events.
- Documented the current gap: prompt construction already includes hidden GM context and bounded history summaries, but there are no first-class owned-item or location records. Generic fact maps and scalar panels do not enforce item identity, transfers, or NPC presence.
- Added an initial sourced desk benchmark of Friends & Fables, Kanka, LegendKeeper, and Apple's interaction-design principles. No competitor flows have yet received hands-on evaluation.
- **Checked:** reviewed the current `Play.State`, `Play.Character`, `Panels.Field`, GM request context, and player play-page projection. No feature code or campaign data was changed in this planning pass.

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
- Reviewed the local connection screen and found the port-4000 process was started before `TokenStore` was added to the supervision tree; `/auth/connect` raises in that stale process. The existing server was left running, and the checkpoint now calls for a restart before account-flow review.

## 2026-09-29 — ChatGPT plan usage cues

- Added a connection-state cue at the play composer: connected players see that the turn uses their ChatGPT plan and can open usage settings; disconnected players can open account setup.
- Added the same usage-settings link to the connected account page and translated all new copy into Spanish and French.
- **Checked:** focused account and session LiveView tests passed (9 tests, 0 failures), the full suite passed (82 tests, 0 failures), and formatting, warnings-as-errors compilation, and asset build passed. A local request to `/auth/connect` returns HTTP 200 under the restarted WSL Phoenix server. The owner has not completed OAuth consent or a live model call.

## 2026-09-29 — Keyboard and reduced-motion affordances

- Added a high-contrast `:focus-visible` outline for interactive elements across the tabletop theme.
- Reduced animation and transition duration for visitors who prefer reduced motion, including pending-turn indicators.
- **Checked:** the frontend asset build passes. Real keyboard navigation, narrow-screen, and screen-reader review are still outstanding.

## 2026-09-29 — Streamed plan-error recovery

- Fixed handling of HTTP error bodies returned as Req `into: :self` asynchronous streams. The error parser consumes bounded response bodies before decoding their JSON error code.
- Added recovery mappings for ChatGPT plan usage, eligibility, and unsupported-route/capability errors so saved turns reach the intended retry guidance instead of a generic provider failure.
- **Checked:** adapter behavior tests passed (9 tests, 0 failures), including synthetic Req async-body messages for HTTP 429, 503, 403, and 400 cases. The full WSL suite passed (83 tests, 0 failures), as did formatting and warnings-as-errors compilation. No live account or model request was made.

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
