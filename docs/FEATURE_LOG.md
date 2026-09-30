# Feature log

## 2026-09-30 — Jump straight to the mobile turn composer

- The sticky session bar begins with a “Your turn” link on playable sessions. It focuses the labeled composer and offsets it below the sticky bar; completed/read-only sessions have no dead composer link.
- **Checked:** LiveView behavior tests cover the focusable target and navigation link. At a 370px browser viewport, keyboard Enter activated the link, focused the composer, and kept the board within viewport width. Visual review also confirmed the translucent amber and white card surfaces stay dark and readable.

## 2026-09-30 — Keep date and time canonical in GM context

- Public world aliases for date, time, and weather now normalize to one canonical key before storage and again when older state is read. Legacy conflicts use the latest matching public state-change event value (or the existing field precedence when history has no matching update); multiple aliases for one fact in a single proposal are rejected. Accepted updates reconcile legacy state before applying the new value.
- The GM request and player-facing board now see the same single date/time/weather values, so old data cannot present one time in the header and another in the scene facts.
- **Checked:** focused Play and SessionLive suites pass (**49 tests, 0 failures**). Behavioral coverage verifies that the latest event value wins over stale persisted aliases, the value appears once on the board and in GM context, newer updates survive reconciliation, state heals to one canonical field, and conflicting aliases in one proposal fail atomically. Isolated `storyteller_test`, fake providers only.

## 2026-09-30 — Preserve dark card contrast on narrow screens

- Added dark palette mappings for translucent amber and white utility backgrounds used by campaign commitments, current-place cards, and nested people/objective rows.
- Darkened amber action colors so cream button labels meet the 4.5:1 contrast target in normal and hover states.
- **Checked:** read-only 370px viewport review confirmed those card surfaces remain dark and readable. The sampled Send action measures 5.13:1 at rest and 4.65:1 on hover. This was a targeted spot check; full contrast and assistive-technology reviews remain open.

## 2026-09-30 — Keep multi-step player travel canonical

- When a turn records multiple player movements, the public world location now uses the final destination, matching the player's persisted current place.
- **Checked:** a behavioral regression verifies final place and world location agree in public projection and in the next session's GM context. It is included in the focused Play and SessionLive run (**49 tests, 0 failures**).

## 2026-09-30 — Page through earlier campaign story

- The campaign timeline starts with a bounded 500-event recent window and exposes a localized “Load earlier story” action for preceding public events. Cursor and DOM identity use immutable event sequence values, so page loads are ordered and idempotent.
- Previously loaded pages remain visible when LiveView refreshes for a new turn. The latest 20 entries stay in the polite additions-only live region; fetched history stays outside it, so reviewing old entries is not announced as new story. Earlier-session markers are computed in one linear pass across loaded history.
- **Checked:** focused Play and SessionLive suites pass (**45 tests, 0 failures**) and the full suite passes (**147 tests, 0 failures**). Tests cover sequence-cursor ordering, 1,101 events across two sessions, repeated loads without duplicates, session headings, and a refresh that appends new activity without dropping loaded pages. WSL formatting, warnings-as-errors compilation, asset build, gettext extraction/merges, and `git diff --check` pass.

## 2026-09-30 — Make campaign resource changes transactional

- Replaced absolute panel-value proposals with strict typed operations: signed deltas for quantity and money, typed sets for text/status/date, and a required grounded reason for every change.
- The commit transaction locks the campaign panel rows, calculates numeric results from the canonical current values, rejects negative balances and no-ops, then persists the new value together with visibility-scoped before/change/after audit events.
- The session timeline shows each resource label, before/after values, delta or set, unit, and reason. Public history omits GM-private panel operations; the GM receives the updated values in later-session context.
- Updated GM policy, checkpoint, and UX acceptance criteria. Reading or reviewing a ledger alone must leave its values unchanged.
- **Checked:** Play, Panels, and SessionLive focused suites **47 tests, 0 failures**; full WSL suite **145 tests, 0 failures**. WSL format check, warnings-as-errors compile, asset build, and `git diff --check` passed. Extracted English keys and merged translated Spanish/French labels. All tests used the isolated `storyteller_test` database and fake providers; no campaign rows were touched.

## 2026-09-30 — Responsive session section shortcuts

- Added a compact sticky in-page navigation bar on narrow session layouts for the scene, current place, campaign story, and inventory. Public objectives and tracked resources appear as shortcuts only when those sections contain public data; the desktop two-column layout stays unchanged.
- Native fragment links move focus to their section targets. The targets have visible keyboard focus treatment and scroll spacing below the sticky bar. The navigation name and reused section labels are available in English, Spanish, and French.
- **Checked:** focused SessionLive suite **11 tests, 0 failures**; full suite **142 tests, 0 failures**; WSL format check, warnings-as-errors compilation, asset build, `git diff --check`, and Spanish/French catalog merges passed.

## 2026-09-30 — Introduce new GM characters during play

- GM proposals can create stable GM-controlled character IDs with public and GM-private facts. The same proposal may let a newly created character speak, act, receive an item, move to a known or newly created place, or receive a fact update.
- Character IDs, facts, owners, speakers, and places are validated before the existing locked commit transaction. New character records are inserted before same-turn dialogue, activity, and location events, so the first encounter remains atomic with its public and GM-private audit entries.
- Public projections and audit events include only names, visible facts, public items, and public presence. GM-private character facts and hidden places and presence remain in GM context and private history across sessions.
- Updated the GM policy, proposal shape, introduction timeline entry, and this checkpoint. No database migration is needed.
- **Checked:** Play behavior tests pass (30 tests, 0 failures), and SessionLive tests pass (9 tests, 0 failures). Coverage includes introduce-and-speak, public presence, hidden-fact and hidden-place continuity across sessions, atomic rejection of duplicate IDs and unknown or malformed place references, and player-visible introduction rendering without private facts. Format check, warnings-as-errors compilation, asset build, and `git diff --check` pass in WSL. No migration was needed.

## 2026-09-30 — Keep roll targets in the story timeline

- Roll-request timeline entries now show the test plus any specified difficulty and target. Players can still see what a D20 result was judged against after resolution or reconnect.
- **Checked:** the SessionLive behavior test checks the request details while awaiting a roll and after reopening the completed session. The display reuses the existing translated labels; no translation catalog or migration change was needed.

## 2026-09-30 — Refresh sourced product benchmark

- Rechecked official Friends & Fables, Craft, Kanka, and LegendKeeper feature pages. The notes now describe the current advertised play and campaign-management features, distinguish those vendor claims from verified behavior, and avoid treating the products as interchangeable.
- Added a consistent hands-on task protocol covering first play, scene/resource discovery, inventory/resource changes, cross-session continuity, recovery, and private facts. No product usability ranking is claimed before those tasks are performed.
- **Checked:** source links point to the official product pages; interactive competitor testing remains outstanding.
- Captured a local request-response baseline for the campaign library, campaign detail, and fictional QA play session: five HTTP 200 GETs per route, with medians of 0.734s, 0.736s, and 0.758s. These development measurements include Windows-to-WSL localhost forwarding and are not a production target.

## 2026-09-30 — Keep inventory canon inside the turn loop

- Decided against direct player writes to canonical inventory in the single-player MVP. Item use, transfers, consumption, and resource changes go through the normal action composer and GM-validated proposals, preserving the story reason and audit trail for accepted changes.
- Reconsider a separate correction request only if playtesting shows the normal action flow cannot reliably resolve mistakes; no player-facing inventory edit screen is planned now.

## 2026-09-30 — Accessible story timeline updates

- Kept the chronological story list mounted from the empty state and marked it as a polite, additions-only live region with non-atomic updates. The first and later appended events can be announced without repeating existing history.
- **Checked:** SessionLive tests verify the live-region attributes on the rendered campaign timeline; the focused suite passes (8 tests, 0 failures). Manual assistive-technology review remains outstanding.

## 2026-09-30 — Genre-flexible resource trade scenario

- Added a fictional Amber Orchard behavior scenario where the GM consumes one basket of produce and increases a typed cash balance in the same turn. The next session's GM context and the public projection both retain the remaining stock and updated cash.
- This tests fungible campaign resources alongside item inventory without using vineyard campaign data.
- **Checked:** the focused Play suite passes (27 tests, 0 failures); full `mix test` passes (136 tests, 0 failures). Format, warnings-as-errors compilation, asset build, and `git diff --check` pass in WSL.

## 2026-09-30 — Amber Orchard D20 playtest

- Exercised a second session in the separate fictional QA campaign with a fake provider. The GM asked for a D20 against target 12; the player's click recorded 16 once, after which the GM completed the turn with dialogue and visible activity.
- A later malformed fake-provider response failed without adding turn events. Retrying the saved action completed once, with one player-action event and one narration event.
- **Checked:** public timeline contains the accepted result, the session page returns HTTP 200 with the resolution, and the GM-private character fact and campaign panel note are absent from player HTML. No live model or OAuth call was made.

## 2026-09-30 — In-play player character details

- GM proposals may add or revise the player's flexible public `visible_facts` when the action establishes a durable detail. Existing unrelated facts stay intact; player updates require a concise action-grounded reason and cannot write GM-private player facts or overwrite name, identity, description, or canonical location keys.
- Player fact patches apply atomically with the turn and create a public audit event containing only the patch and reason. The timeline identifies the character-detail update and explains its reason. GM-controlled characters keep their existing split public/private fact updates.
- Updated the GM policy and proposal shape, and refreshed the product benchmark's remaining-gaps list. Spanish and French timeline labels and reason copy are translated.
- **Checked:** focused Play and SessionLive suites pass (34 tests, 0 failures), covering public updates, later-session context, board rendering, reasoned audit history, private/missing-reason/unknown-ID/identity rejection, rollback, and existing GM-character updates. Full `mix test` passes (136 tests, 0 failures).

## 2026-09-30 — Flexible player character details in campaign setup

- Campaign setup accepts up to 50 optional player-visible label/value details, with bounded labels and values and case-insensitive duplicate-label rejection. These flexible facts are stored alongside the existing player-character description; no RPG-specific fields or migration were added.
- The setup review shows the selected details before creating the campaign. The existing player character projection feeds them into the player board and GM context. Setup copy and validation messages are translated in Spanish and French.
- **Checked:** focused Campaigns and CampaignLive setup suites pass (24 tests, 0 failures), including setup-to-facts-to-board/context persistence and invalid, oversized, and duplicate rows. The focused Campaigns, CampaignLive, and LocaleLive run passes (30 tests, 0 failures), including Spanish and French row labels/placeholders. Format check, warnings-as-errors compile, asset build, and diff check pass in WSL.

## 2026-09-30 — Readable item details and canonical location

- The inventory disclosure now renders generic properties as escaped key/value rows, with humanized nested paths and compact map/list values. It retains a native keyboard-accessible disclosure.
- The play-board location rail now prefers the player's canonical current place over a stale world-location string.
- **Checked:** the session LiveView suite passes (7 tests, 0 failures), including nested properties, escaped values, and a regression test for a stale location string. Full `mix test` passes (132 tests, 0 failures); formatting, warnings-as-errors compilation, asset build, and `git diff --check` pass in WSL.

## 2026-09-30 — Safe item property updates

- Added a GM-proposed `update` operation limited to an existing item's flexible `properties` map. Nested objects merge recursively, preserving unrelated keys and enforcing the same JSON depth and node limits on the merged result.
- Updates preserve stable item identity and all other canonical item fields. They validate sequentially with add, transfer, and consume operations; any later invalid operation rejects the full proposal before inventory changes or audit events commit.
- Audit visibility follows the item: public updates appear in public history without the GM's reason, while private update details and reasons stay in GM-private history. Canonical model context carries the updated properties into later turns and sessions.
- Updated the GM policy and operation schema with the properties-only rule.
- The player board displays changed properties in its readable item-details disclosure.
- **Checked:** focused inventory domain and Play behavior suites pass (44 tests, 0 failures). Focused formatting, warnings-as-errors compilation, `mix assets.build`, and `git diff --check` pass in WSL.

## 2026-09-30 — Inventory actions from the play board

- Added a localized action button to public player- and party-owned inventory items. It appends a short item-use sentence in the campaign narration language, preserves the current composer draft, and focuses the textarea for review and editing.
- The server only uses item data found in the session's public inventory projection and silently ignores hidden, unknown, or NPC-owned item IDs. The player still submits the normal turn explicitly; the button does not change inventory or create a turn.
- **Checked:** focused session LiveView tests pass (6 tests, 0 failures), covering all three narration languages, interface-language independence, draft append/edit behavior, ownership filtering, forged IDs, and no inventory or timeline mutation before submission. `mix format` passed.

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
