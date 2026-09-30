# Storyteller MVP implementation plan

> **Selected direction (2026-09-29):** Build a standalone Phoenix LiveView site that runs locally and use Sign in with ChatGPT's preview ChatGPT-plan usage flow for GM inference. The owner has ChatGPT Plus and does not plan to buy API credits. This route is for eligible open-source, locally hosted apps, and has preview limitations and shared plan usage limits. Confirm eligibility and the GM request shape in the first implementation milestone before building the full turn loop. A conventional API-key integration remains a separately priced fallback only if the owner's budget changes.
>
> **License:** MIT, selected by the owner on 2026-09-29 and applied in `LICENSE`.

## Goal and scope

Build a private, single-player TTRPG experience that can continue the existing vineyard campaign and host new campaigns. The chosen MVP play surface is an independent Phoenix LiveView website running on the owner's computer, with game state stored locally. Model inference uses the owner's consented ChatGPT plan through OAuth while the app is running locally. Do not expose it as a remotely hosted service or share the OAuth credentials. One campaign can contain many play sessions; a session is a resumable segment of the campaign's continuous history. The first release supports one human player per campaign. Multiplayer, voice, maps, payments, and a general rule-system editor are outside the MVP.

The interface is a Phoenix LiveView application. It should update the turn timeline, character activity, world state, and campaign panels without full page reloads. Keep browser JavaScript small and limited to interactions that need it, such as optional die animation. Bind the web server and local database to loopback by default so the personal campaign site is not exposed to the network.

## Chosen play surface and account model

OpenAI lists Plus and conventional API-key use separately; API-key calls follow per-token pricing. The selected route is the documented [ChatGPT-plan usage flow for eligible open-source and locally hosted apps](https://developers.openai.com/siwc/token-sharing-open-source). It authorizes supported Responses API calls using an OAuth access token granted by the owner. It is in preview, shares the owner's Plus usage allowance with other ChatGPT apps, and does not grant access to existing ChatGPT conversations. Do not automate the ChatGPT website or reuse its browser session as a substitute. Keep the repository open source and verify the project's eligibility before relying on this route. If the site is later hosted remotely or offered as a paid app, OpenAI says to use its interest process; that is outside this plan.

The chosen product path is:

1. **Standalone local site with ChatGPT-plan OAuth:** Run Phoenix and its database on the owner's computer, open the site in the browser, and keep campaign content in the app's local database. The player interacts in the website, not in ChatGPT. The app signs in through OpenAI's open-source client flow and calls the public Responses API with the owner's OAuth bearer token. This is the preferred MVP and does not use an API key or per-token API billing, subject to eligibility, the preview's supported features, and Plus limits.

### OAuth and local credential requirements

- Keep the application open source and locally hosted. Before relying on the preview, confirm the current eligibility and any OSS registration terms. If the owner later wants remote access, remote hosting, or a paid distribution, treat that as a new product decision and obtain the required OpenAI eligibility first.
- First sign-in dynamically registers the local app using its actual app name and a persistent, opaque `ext_agent_host_id`; reuse the issued `client_id` for that ChatGPT account. Each distinct local host has its own stable host ID. This flow does not require an API key or client secret.
- Start authorization in the system browser using the documented loopback callback on `127.0.0.1`, OAuth authorization code with PKCE S256, fresh `state` and OIDC `nonce`, and the `https://api.openai.com/v1` resource. Request identity scopes plus `offline_access`, `resource.invoke`, and `chatgpt.tokens.use.direct`. Validate the callback, granted scopes, ID-token signature, issuer, audience, expiry, nonce, and account identity before enabling GM calls.
- Store the issued client ID, verified account identity, host ID, ID token, access token, refresh token, granted scopes, and expiries in protected local server-side storage. Never put credentials in browser storage, source control, logs, or analytics. Access tokens last one hour; refresh tokens last 30 days and rotate on successful refresh. Serialize refresh operations. Revoke the renewable session on sign-out and clear local tokens. A compromised account can disconnect the app from ChatGPT settings.
- Send inference requests only to `POST https://api.openai.com/v1/responses` with the OAuth bearer access token and a model available to the signed-in account. Load the account's available model list instead of hardcoding an unavailable model. Treat eligible responses as subscription usage, not API key spend.

### Preview request constraints

- For every HTTP Responses request, set `store: false` and `stream: true`, and send the complete needed context as an `input` array. Put GM instructions in `instructions` or developer messages; explicit system-role message items are rejected.
- Do not send `previous_response_id` or rely on provider-side conversation storage. The local database and summary builder are authoritative for campaign history and continuity.
- Omit unsupported request fields: `background`, `conversation`, `max_output_tokens`, `max_tool_calls`, `metadata`, `moderation`, `multi_agent`, `prompt`, `prompt_cache_retention`, `safety_identifier`, `temperature`, `top_logprobs`, `top_p`, `truncation`, and `user`.
- Use supported function/custom tools only, grouped in namespaces or supplied as `additional_tools` input items. The preview does not support hosted MCP/connectors, Responses `tool_search`, image generation, file search, Code Interpreter, native computer use, audio/video inputs, Files upload API, or transcription API. The MVP only needs text and app-side campaign state, so it should not depend on these hosted tools.
- Consume the stream through a terminal event and apply game changes only after `response.completed` and application validation. Handle unsupported-capability errors by correcting the request, not retrying the same body. On a usage-limit error, stop new GM requests and show the user where to check ChatGPT usage; do not silently fall back to paid API calls. On temporary usage-unavailable errors, preserve turn state and retry later with bounded backoff. If the account or workspace is ineligible, show the sign-in limitation and stop.

### Monthly inference cost estimate

The selected OAuth route has no separate per-token API charge; it consumes the owner's existing ChatGPT Plus allowance. The current listed Plus subscription is $20/month. The owner already has that plan, so Storyteller's estimated additional model charge on this route is $0/month while requests remain eligible and within plan limits. The Plus allowance is shared with other apps and work in the account, so price is predictable but available play capacity is not guaranteed. Local hosting avoids a hosting bill for the MVP if it runs on the owner's existing computer; domain, remote hosting, and any infrastructure the owner later chooses are excluded.

For comparison only, the conventional API-key route would add token charges to Plus. These planning estimates use GPT-6 Sol standard rates ($2 per million input tokens and $10 per million output tokens), 30 play days per month, one GM call per reply, and no cache discount:

| Daily play scenario | Assumed tokens per GM reply (input / output) | Added API estimate per month | Total including existing Plus |
| --- | ---: | ---: | ---: |
| Short: 5 GM replies/day | 12,000 / 1,500 | $5.85 | $25.85 |
| Long: 20 GM replies/day | 25,000 / 2,000 | $42.00 | $62.00 |

Token volumes are assumptions for budgeting, not measured usage. Longer conversation context, extra model calls, or different model choice can raise the API estimate; prompt caching can reduce it. The OAuth route can instead pause when Plus limits are reached, without purchasing credits.

## Preserve the vineyard game and its GM rules

1. Review the complete vineyard conversation or obtain an authoritative export. The original chat is accessible read-only through conversation history, but long retrieved messages may be truncated; do not reconstruct missing facts from partial messages.
2. Extract a dated timeline, player character, GM-controlled characters, relationships, locations, resources, commitments, open decisions, and current world state. Mark uncertain or conflicting facts for owner review. Import the approved result into a private campaign, with the source transcript retained as an archive outside the public Git repository.
3. Store the shared GM policy as the versioned, campaign-independent `docs/GM_POLICY.md`. The original vineyard conversation establishes these behaviours:
   - React to player actions with natural consequences; ordinary actions can remain ordinary.
   - Let scenes breathe. Escalation, mysteries, and revelations require an established cause or prior clues.
   - Give NPCs their own knowledge, motives, and agency.
   - Never decide the player's actions, speech, thoughts, or choices.
   - Roll only for uncertain, consequential actions. Ask the player to roll for player-controlled characters; resolve GM-controlled checks on the GM side.
   - Describe the outcome, let the world respond, and return control to the player.
   - The GM advances the calendar and weather, and every turn keeps the in-world date visible.
4. Separate that policy from each campaign's setting, tone, characters, and mechanics. During vineyard import, review any campaign-specific rules against the full transcript before treating them as canonical.

## Product behaviour

### Product quality priorities

- Deliver the full play experience, not just a beautiful shell: a player should be able to follow the campaign, understand their character's current situation, act with confidence, and pick up the same world later.
- Give the player a clear character board for their current place, surroundings, immediate situation, known character details, and owned items or resources. Present only information the character would know. Keep campaign-specific information configurable so the same interaction supports an adventurer's equipment and a vineyard's wine stock and cash.
- Treat the model as the narrator and proposer, not the source of truth. Durable world facts, character presence, possessions, resources, and accepted events live in the local database. Give the GM concise hidden context for private motives and unresolved facts, while deriving player views only from public state.
- Validate state-changing proposals against canonical entities and safe campaign-defined schemas. Apply accepted changes atomically with a traceable event; reject unknown entities, invalid ownership or quantities, and unapproved changes. A narrative sentence must not silently create or remove a tracked item.
- Benchmark both AI-native play tools and campaign-management tools before finalizing this information model. Use their useful interaction patterns as evidence, not as a feature checklist. Apply Apple's documented principles of purpose, agency, responsibility, familiarity, feedback, flexibility, simplicity, craft, and delight to the web experience without copying Apple platform styling.
- Balance appearance work with usability, play quality, continuity, accessibility, and recovery. A visual iteration is complete only when the relevant play task remains clear and usable.

### Campaigns and sessions

- A campaign creation flow accepts a title, story premise, setting, tone, language, player character details, optional GM-controlled characters, initial location/date/weather, and any campaign-specific mechanics. A review step shows the setup before play begins.
- The owner can create, list, open, resume, and archive campaigns. Within a campaign they can start and switch between sessions without losing the continuous campaign state or turn history.
- The play screen has a turn timeline, a text input for what the player does or says, a D20 control, a compact world-state header, a character activity area, and configurable campaign panels. The layout adapts to narrow screens.

### Turns, characters, and the D20

- Each completed turn records the player's text, GM narration, NPC dialogue as speaker-attributed speech bubbles, the visible activity of relevant GM-controlled characters, world changes, and any rolls. The GM also maintains private facts and offstage activity without exposing spoilers in the player view.
- The player initiates each D20 roll by clicking the die. The server generates and records the result. When a player action needs a roll, the GM states what is being tested and the difficulty or target before the player rolls; the result then goes back into resolution. The GM never silently rolls for a player-controlled character. GM-controlled checks use a separate server-side roll path.
- A turn can be pending, awaiting a player roll, completed, or failed. Disable duplicate submissions, show progress while the GM responds, and allow a failed turn to be retried without duplicating events or applying state twice. A refresh or reconnect must restore the same pending or completed turn.

### World and campaign panels

- Maintain canonical, persisted state for location, in-world date/time, weather, characters, and campaign resources. Do not rely on prose or model memory as the only source of truth.
- Provide an at-a-glance, player-facing character board for the present scene and current character details. It should make place, surroundings, immediate activity, visible NPC presence, and character resources findable during play, without forcing players to scan the whole transcript.
- Support a flexible, campaign-defined inventory and resource model. Dungeon campaigns need named items, consumables, equipment, quantities, and ownership; a vineyard may need cash, wine stock, vine stock, or other domain-specific quantities. Track stable identities and ownership so updates change the correct item instead of an ambiguous label. Avoid arbitrary executable formulas in the MVP.
- Define safe field types, units, visibility, and editable schemas. Existing quantity, money, text, status, and date fields can cover simple ledgers, including cash and wine/vine levels, but they do not replace a first-class owned-item inventory when items have identity or per-character ownership.
- Keep a canonical place/character-presence record so an NPC's known location and a character's movement can be checked against accepted events. Show private GM facts only in prompts and never in player projections.
- Track optional campaign-scoped objectives with stable IDs, `open`, `completed`, and `abandoned` status, and public or GM-private visibility. The GM prompt receives both canonical visibility scopes; ordered, reasoned create/update proposals validate against prior operations and commit with their visibility-safe audit events. The player board shows public objectives by status across sessions.
- Keep an append-only record of player actions, rolls, GM outputs, and applied state changes, with current state snapshots for quick loading. Every visible value should be traceable to a turn or an explicit setup/edit action.

### GM continuity and canon

- Assemble each GM request from the versioned play policy, campaign setup, the latest canonical public state, the private GM state, typed character and inventory facts, current character locations, the most recent events across sessions, and separate public/private continuity summaries.
- Treat summaries as navigation aids, not as replacements for canonical inventory, location, ownership, or unresolved facts. Older events remain inspectable even when they leave the bounded prompt window.
- Require proposed changes to identify stable records and explicit operations such as add, remove, transfer, move, or update. Validate quantities and permitted destinations before committing; record accepted deltas with the turn and refresh snapshot state atomically.
- Keep private facts in the GM context and private event history. Public timeline, character board, campaign panels, validation errors, and reconnect state must not disclose them.

## Technical design for the selected local site

Use Phoenix, LiveView, Ecto, and PostgreSQL. A small set of domain contexts should own campaigns/sessions, characters/world state, turn resolution, rolls, and AI integration. LiveViews render and dispatch actions; domain functions enforce rules and persistence.

Suggested records: owner account, campaign, session, character, turn, roll, world-state snapshot, campaign field definition/value, and GM run metadata. Core relationships and frequently queried fields belong in typed columns. Flexible campaign-specific state can use validated JSON fields. Split public and GM-private facts at the data boundary and check visibility before rendering.

For each player action:

1. Persist one pending turn with an idempotency key and lock that campaign's resolution path.
2. Build model context from the versioned GM policy, campaign setup, canonical state, relevant recent turns, and a maintained summary of older history. Store enough local history to resume without depending on provider conversation retention.
3. Request a structured GM response: narration blocks, attributed dialogue, character activities, proposed state changes, and either a roll request or a final outcome. Treat model output as a proposal; validate speaker IDs, visibility, units, allowed changes, and schema before applying it.
4. If a player roll is requested, pause the turn. Accept the player's die click, record the server-generated result, and continue resolution with that result. GM-controlled rolls use the same audited roll service without a player click.
5. Commit the accepted output, roll references, and state changes together. Publish the completed turn to LiveView. On timeout or invalid output, keep the previous canonical state, surface a recoverable error, and retain diagnostics without storing secrets.

For the selected local route, use the OpenAI Responses API behind the provider behaviour with a bearer token issued by the ChatGPT-plan OAuth flow. Stream each GM response and validate it before applying state changes. Verify the exact supported output format and tool-call shape in the feasibility milestone; if structured output fields are unsupported, use a supported function/custom tool or parse a constrained text payload and validate it locally. The database remains authoritative for campaign continuity. Keep the conventional API-key provider as a possible future adapter, but do not make its credentials or billing the MVP default.

## Internationalization

- Ship the full interface in English, Spanish, and French using Gettext: navigation, forms, errors, dates, numbers, dice labels, and campaign panel chrome.
- Persist a user interface locale preference and a campaign narration language separately. A change of interface locale should update labels without translating or rewriting existing turns. Prompt the GM in the campaign narration language; store each turn in the language in which it was produced.
- Keep user-authored names, story text, and custom field labels as entered. Provide clear fallbacks for untranslated custom content. Test all three locales in the campaign setup and play flows.

## Test strategy and acceptance criteria

Tests should assert observable behaviour and durable state, not internal class or module shapes. Run the normal suite without live AI calls using a fake GM provider and fixed roll source. Test OAuth state, PKCE callback validation, consent refusal, missing plan-usage scope, account mismatch, refresh rotation, revoke/sign-out, usage-limit pause, and temporary service errors separately from domain behaviour. Cover pure domain rules with extensive unit tests, persistence with Ecto tests, and user flows with LiveView tests. Keep a small, opt-in live-provider smoke check for the selected local OAuth route; use human-reviewed scenario evaluations for nondeterministic GM quality instead of exact-prose snapshots.

Required behavioural scenarios:

- Create two campaigns, configure different stories and characters, and switch between them without state leakage.
- Start multiple sessions in one campaign and resume the later session with prior state and history intact.
- Submit player action/speech and see narration, correct NPC speech bubbles, current NPC activity, and updated world state without a page refresh.
- Request a consequential player roll, show the target first, wait for the player's click, record a D20 result, and resolve exactly once. An ordinary action should not trigger a roll.
- Update vineyard cash or inventory through an accepted event and see the configured panel reflect the new value; reject an invalid or hidden state change.
- Create a dungeon-style inventory with distinct owned items and consumables; add, consume, and transfer an item by stable identity, and verify no action duplicates or removes the wrong item. Create a vineyard-style resource panel and verify money and product quantities remain correct across multiple sessions.
- Move a character between known places and verify the accepted location is visible to the player only when appropriate and reaches the next GM prompt as canonical context. Reject references to unknown characters or destinations; verify NPCs do not appear in an unrelated location without an accepted move or established event.
- Attempt to gain, lose, duplicate, or transfer a tracked item through narration alone. The item ledger must remain unchanged unless the proposal contains a valid accepted state delta, and the player can trace a committed change to its event.
- Seed private motives, hidden places, and secret inventory in the separate GM context. Verify the GM receives them while player-facing views, state-change events, and reconnect output omit them.
- Create and update campaign commitments across two sessions. Verify public objectives persist and advance, GM-private objectives stay in GM context and private history, malformed ordering or duplicate IDs applies no partial changes, and the board groups public open/completed/abandoned objectives in all three locales.
- Survive provider timeout, invalid model output, refresh, reconnect, and repeated submit without a duplicate turn or partial state change.
- Change among English, Spanish, and French and see interface text and formatting change while stored story text remains intact.
- Review GM scenario fixtures for natural consequences, player agency, restrained escalation, consistent facts, and independent NPC behaviour.

No feature is done until its relevant behavioural tests pass. Add focused unit tests for edge cases and invariants, including turn status transitions, dice range, resource arithmetic, visibility, and migration reconciliation. Avoid tests that merely repeat implementation details.

## Delivery sequence

Milestones 2–6 describe the shared domain goals and selected standalone UI. Only revise the play surface if the OAuth feasibility check fails and the owner chooses another route.

1. **Validate the selected OAuth route and source material.** Keep the app open source and confirm local-app eligibility. Prototype first-time and returning OAuth sign-in, token refresh, logout/revocation, model listing, and one streamed Responses call using the preview's allowed request fields. Prove the GM response can carry narration, dialogue, and proposed changes in a locally validated format. Confirm the app does not run as a remote service or send credentials to the browser. Confirm the single-player access model, vineyard transcript availability, and exact campaign mechanics. Produce a reviewed migration inventory and GM policy. Exit: OAuth plan usage succeeds for the owner's account, required GM behaviour fits the supported API subset, and no critical vineyard fact is inferred solely from the incomplete excerpt. If this gate fails, stop before building the turn loop and revisit the product or billing decision with the owner.
2. **Establish the application and data model.** Scaffold Phoenix/LiveView, private owner access, PostgreSQL/Ecto records, campaign/session creation, and test fixtures. Exit: campaigns and sessions persist, remain isolated, and can be resumed.
3. **Implement canonical state and configurable panels.** Add characters, visible/private state, resource fields, event history, snapshots, and vineyard panel configuration. Exit: explicit state changes are validated, traceable, and rendered.
4. **Implement the GM turn loop and dice.** Add provider behaviour, context assembly, structured output validation, pending turns, the player's explicit D20 click, retries, and atomic state application. Do not add GM rolls unless a campaign's rules call for a distinct audited roll. Exit: the key turn and failure scenarios pass with a fake provider.
5. **Build the LiveView play experience.** Add responsive timeline, NPC speech bubbles and activity, world header, campaign panels, text composer, die, progress and recovery states. Exit: complete play flow works without full page refreshes and survives reconnects.
6. **Add the campaign board and robust campaign canon.** The first vertical slice now includes typed item ownership and whole/partial stack transfers, campaign-scoped public/GM-private places and character presence, durable public/GM-private objectives with ordered create/update proposals and status history, and flexible player-character details that the GM can update publicly with reasoned audit history. Continue with wider genre scenarios and decide whether players need an auditable correction request for inventory after setup; in-world item changes remain GM-proposed and validated. Exit: inventory, movement, objectives, and player-visible character facts remain canonical over multiple sessions; fact changes preserve visibility and reject invalid batches with a fake provider.
7. **Benchmark, localize, and harden.** Compare the public feature sets of AI-native play and campaign-management products, then review task flows against the acceptance criteria and Apple design principles. Complete three locales, import the reviewed vineyard state, run behavioral and GM scenario suites, check accessibility and mobile layout, and exercise an opt-in live-provider smoke flow. Exit: the vineyard campaign can continue from its approved state and a fresh campaign can be created and played.

**Implementation checkpoint (2026-09-30):** Campaign setup can seed player-owned items and up to 50 flexible player-character facts; the GM can add or revise those public facts with an action-grounded reason, while private player-fact and core identity writes are rejected. Changes are atomic, recorded in a public visibility-safe timeline event, and persist into later-session GM context and the player board. Persisted inventory supports validated add, whole/partial stack transfer, and consume operations; public player/party inventory items can prefill the editable action composer without changing state; canonical places store public or GM-private surroundings; characters keep campaign-scoped current-place IDs; and optional objectives store stable IDs, visibility, and open/completed/abandoned status. Ordered objective create/update changes validate against existing and earlier proposed changes and commit with the turn and audit events. The model receives canonical places, presence, inventories, and both objective visibility scopes, while the board and public timeline expose public objectives only. Free-form world changes cannot overwrite inventory or location. Tests cover quantity conservation, action-prefill safety, movement, objective progression across sessions, private-objective isolation, duplicate/invalid objective rollback, player-fact continuity, public reason events, the fictional harvest-sale ledger scenario, and the three-status board. Remaining work includes deciding whether an auditable inventory correction workflow is needed, hands-on benchmarking, mobile/assistive-technology QA, the opt-in OAuth smoke flow, and approved vineyard import.

## Implementation workflow, persistence, and test isolation

- The product owner coordinates parallel coding agents, reviews the user-visible result and behaviour, integrates work, and keeps iterating against this plan. Prefer GPT-6 Sol at high reasoning effort for product-owner work and GPT-6 Luna at xhigh for coding agents when those settings are available; otherwise retain the active settings.
- Run all Erlang, Elixir, Mix, Phoenix, and project test commands in WSL 2 or a Linux VM. Do not use the Windows Elixir installation. Keep PostgreSQL's development data in durable local storage that survives WSL/app restarts; do not use an ephemeral database for the campaign that is played over multiple days. Keep database files, dumps, OAuth tokens, and other secrets out of Git.
- Maintain a fictional, explicitly separate QA campaign for manual feature testing. Never use, overwrite, or import the vineyard campaign for product or regression tests. Automated tests use a separate test database and isolated fixtures. The QA campaign must remain separate from any future approved vineyard import.
- Add a concise `docs/FEATURE_LOG.md` entry for each user-visible feature or meaningful behaviour change, including how it was checked. Update this plan when product decisions or architecture constraints change. Do not create a README yet, per the owner's repository preference.
- The owner authorizes commits directly to `main` and pushes to GitHub until the MVP is workable and polished. The product owner reviews agent changes, focused behavioral tests, and documentation before integrating and pushing each coherent iteration.

## Risks and decisions to track

- **Account access:** The chosen OAuth route is a preview for eligible open-source, locally hosted apps. The user's Plus allowance is shared with other apps and can stop GM requests at a usage limit; the app must pause cleanly and must not switch to billed API calls. Remote hosting requires a separate eligibility process. Conventional API-key usage is a future option only if the owner changes the budget.
- **Legacy history:** The original chat is accessible read-only, but long retrieved messages may be truncated. Review the whole timeline and obtain an authoritative export or owner-approved summary before importing private campaign state.
- **Model fallibility:** A structured or constrained response reduces parsing ambiguity but does not guarantee correct fiction or arithmetic. Validate changes, keep the canonical state in the application, and preserve a reviewable event record.
- **Continuity drift:** LLM-generated summaries can omit, merge, or contradict details. Stable item, location, character, and relationship records plus event-linked state deltas are required before relying on the product for a long-running campaign.
- **Session meaning:** This plan treats a session as a segment inside a campaign. Confirm that model during the creation-flow review if the owner intends independent branches instead.

## Reference documentation

- [OpenAI API quickstart](https://developers.openai.com/api/docs/quickstart) and [production best practices](https://developers.openai.com/api/docs/guides/production-best-practices) for API credentials and usage limits.
- [ChatGPT pricing](https://learn.chatgpt.com/docs/pricing) for the current Plus subscription reference and usage-limit guidance.
- [ChatGPT plan usage for open-source and locally hosted apps](https://developers.openai.com/siwc/token-sharing-open-source), [models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), and [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) for the local OAuth candidate.
- [OAuth registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions), [token reference](https://developers.openai.com/siwc/token-sharing-open-source/token-reference), and [errors and recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery) for credentials, renewal, usage limits, and sign-out.
- [GPT-6 Sol pricing](https://developers.openai.com/api/docs/models/gpt-6-sol) for the API-key comparison estimate. Prices and plan terms should be rechecked before implementation and before making future cost promises.
- [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs) and [conversation state](https://developers.openai.com/api/docs/guides/conversation-state) for the GM adapter.
- [Phoenix LiveView guide](https://phoenix.hexdocs.pm/live_view.html), [LiveView testing](https://phoenix-live-view.hexdocs.pm/1.2.11/Phoenix.LiveViewTest.html), and [Gettext](https://gettext.hexdocs.pm/) for the server-rendered interface, behavioural tests, and localization.
- [Initial product benchmark and design principles](docs/PRODUCT_BENCHMARK_2026-09.md) for the comparison set, sourced feature observations, product implications, and interaction-design guidance.
