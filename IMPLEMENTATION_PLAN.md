# Storyteller MVP implementation plan

## Goal and scope

Build a private, single-player TTRPG website that can continue the existing vineyard campaign and host new campaigns. One campaign can contain many play sessions; a session is a resumable segment of the campaign's continuous history. The first release supports one human player per campaign. Multiplayer, voice, maps, payments, and a general rule-system editor are outside the MVP.

The interface is a Phoenix LiveView application. It should update the turn timeline, character activity, world state, and campaign panels without full page reloads. Keep browser JavaScript small and limited to interactions that need it, such as optional die animation.

## First decision: how the GM is powered

An external website needs an OpenAI API project and server-side API credential. The owner may use their personal OpenAI account to own that project, but the ChatGPT website session or subscription is not the site's API credential. API usage has its own billing and limits. Confirm that this interpretation satisfies the personal-account requirement before implementing the AI adapter. If subscription-only access is essential, revisit the product surface before building the GM integration.

Keep the credential in server-side configuration or a secret store, never in the browser, database exports, logs, or Git. Make model selection, request limits, and a monthly spending cap configurable. Define a small GM provider behaviour so tests use a deterministic fake and a future provider change does not affect game rules.

## Preserve the vineyard game and its GM rules

1. Obtain the complete vineyard conversation or an authoritative export. The currently accessible chat excerpt is incomplete; do not reconstruct missing history from the latest messages.
2. Extract a dated timeline, player character, GM-controlled characters, relationships, locations, resources, commitments, open decisions, and current world state. Mark uncertain or conflicting facts for owner review. Import the approved result into a private campaign, with the source transcript retained as an archive outside the public Git repository.
3. Store the shared GM policy as a versioned, campaign-independent rules document. The accessible generic GM framework establishes these behaviours:
   - React to player actions with natural consequences; ordinary actions can remain ordinary.
   - Let scenes breathe. Escalation, mysteries, and revelations require an established cause or prior clues.
   - Give NPCs their own knowledge, motives, and agency.
   - Never decide the player's actions, speech, thoughts, or choices.
   - Roll only for uncertain, consequential actions. Ask the player to roll for player-controlled characters; resolve GM-controlled checks on the GM side.
   - Describe the outcome, let the world respond, and return control to the player.
4. Separate that policy from each campaign's setting, tone, characters, and mechanics. During vineyard import, review any campaign-specific rules against the full transcript before treating them as canonical.

## Product behaviour

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
- Define campaign panel fields with safe data types such as quantity, money, text, status, and date, plus units and visibility. The vineyard configuration can show cash, wine inventory, and vine inventory. New campaigns can choose different fields without application code changes. Avoid arbitrary executable formulas in the MVP.
- Keep an append-only record of player actions, rolls, GM outputs, and applied state changes, with current state snapshots for quick loading. Every visible value should be traceable to a turn or an explicit setup/edit action.

## Technical design

Use Phoenix, LiveView, Ecto, and PostgreSQL. A small set of domain contexts should own campaigns/sessions, characters/world state, turn resolution, rolls, and AI integration. LiveViews render and dispatch actions; domain functions enforce rules and persistence.

Suggested records: owner account, campaign, session, character, turn, roll, world-state snapshot, campaign field definition/value, and GM run metadata. Core relationships and frequently queried fields belong in typed columns. Flexible campaign-specific state can use validated JSON fields. Split public and GM-private facts at the data boundary and check visibility before rendering.

For each player action:

1. Persist one pending turn with an idempotency key and lock that campaign's resolution path.
2. Build model context from the versioned GM policy, campaign setup, canonical state, relevant recent turns, and a maintained summary of older history. Store enough local history to resume without depending on provider conversation retention.
3. Request a structured GM response: narration blocks, attributed dialogue, character activities, proposed state changes, and either a roll request or a final outcome. Treat model output as a proposal; validate speaker IDs, visibility, units, allowed changes, and schema before applying it.
4. If a player roll is requested, pause the turn. Accept the player's die click, record the server-generated result, and continue resolution with that result. GM-controlled rolls use the same audited roll service without a player click.
5. Commit the accepted output, roll references, and state changes together. Publish the completed turn to LiveView. On timeout or invalid output, keep the previous canonical state, surface a recoverable error, and retain diagnostics without storing secrets.

Use the OpenAI Responses API behind the provider behaviour. Structured outputs can supply renderable blocks and proposed state changes. The database remains authoritative for campaign continuity. Start with completed responses and a LiveView progress state; consider streaming later if latency warrants it and state validation still precedes commit.

## Internationalization

- Ship the full interface in English, Spanish, and French using Gettext: navigation, forms, errors, dates, numbers, dice labels, and campaign panel chrome.
- Persist a user interface locale preference and a campaign narration language separately. A change of interface locale should update labels without translating or rewriting existing turns. Prompt the GM in the campaign narration language; store each turn in the language in which it was produced.
- Keep user-authored names, story text, and custom field labels as entered. Provide clear fallbacks for untranslated custom content. Test all three locales in the campaign setup and play flows.

## Test strategy and acceptance criteria

Tests should assert observable behaviour and durable state, not internal class or module shapes. Run the normal suite without live AI calls using a fake GM provider and fixed roll source. Cover pure domain rules with extensive unit tests, persistence with Ecto tests, and user flows with LiveView tests. Keep a small, opt-in live-provider smoke check for credentials and schema compatibility; use human-reviewed scenario evaluations for nondeterministic GM quality instead of exact-prose snapshots.

Required behavioural scenarios:

- Create two campaigns, configure different stories and characters, and switch between them without state leakage.
- Start multiple sessions in one campaign and resume the later session with prior state and history intact.
- Submit player action/speech and see narration, correct NPC speech bubbles, current NPC activity, and updated world state without a page refresh.
- Request a consequential player roll, show the target first, wait for the player's click, record a D20 result, and resolve exactly once. An ordinary action should not trigger a roll.
- Update vineyard cash or inventory through an accepted event and see the configured panel reflect the new value; reject an invalid or hidden state change.
- Survive provider timeout, invalid model output, refresh, reconnect, and repeated submit without a duplicate turn or partial state change.
- Change among English, Spanish, and French and see interface text and formatting change while stored story text remains intact.
- Review GM scenario fixtures for natural consequences, player agency, restrained escalation, consistent facts, and independent NPC behaviour.

No feature is done until its relevant behavioural tests pass. Add focused unit tests for edge cases and invariants, including turn status transitions, dice range, resource arithmetic, visibility, and migration reconciliation. Avoid tests that merely repeat implementation details.

## Delivery sequence

1. **Resolve prerequisites and source material.** Confirm the API-project interpretation, cost limit, single-player access model, vineyard transcript availability, and exact campaign mechanics. Produce a reviewed migration inventory and GM policy. Exit: no critical vineyard fact is inferred solely from the incomplete excerpt.
2. **Establish the application and data model.** Scaffold Phoenix/LiveView, private owner access, PostgreSQL/Ecto records, campaign/session creation, and test fixtures. Exit: campaigns and sessions persist, remain isolated, and can be resumed.
3. **Implement canonical state and configurable panels.** Add characters, visible/private state, resource fields, event history, snapshots, and vineyard panel configuration. Exit: explicit state changes are validated, traceable, and rendered.
4. **Implement the GM turn loop and dice.** Add provider behaviour, context assembly, structured output validation, pending turns, player-initiated D20, GM rolls, retries, and atomic state application. Exit: the key turn and failure scenarios pass with a fake provider.
5. **Build the LiveView play experience.** Add responsive timeline, NPC speech bubbles and activity, world header, campaign panels, text composer, die, progress and recovery states. Exit: complete play flow works without full page refreshes and survives reconnects.
6. **Localize, migrate, and harden.** Complete three locales, import the reviewed vineyard state, run behavioural and GM scenario suites, check accessibility and mobile layout, and exercise an opt-in live-provider smoke flow. Exit: the vineyard campaign can continue from its approved state and a fresh campaign can be created and played.

## Risks and decisions to track

- **Account access:** An API key and API billing are prerequisites for an independent website. The precise model and budget can be selected after testing quality and latency with the GM scenarios.
- **Legacy history:** The accessible vineyard excerpt is incomplete. A full export or authoritative owner-supplied summary is needed for faithful continuation.
- **Model fallibility:** Structured output reduces parsing ambiguity but does not guarantee correct fiction or arithmetic. Validate changes, keep the canonical state in the application, and preserve a reviewable event record.
- **Session meaning:** This plan treats a session as a segment inside a campaign. Confirm that model during the creation-flow review if the owner intends independent branches instead.

## Reference documentation

- [OpenAI API quickstart](https://developers.openai.com/api/docs/quickstart) and [production best practices](https://developers.openai.com/api/docs/guides/production-best-practices) for API credentials and usage limits.
- [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs) and [conversation state](https://developers.openai.com/api/docs/guides/conversation-state) for the GM adapter.
- [Phoenix LiveView guide](https://phoenix.hexdocs.pm/live_view.html), [LiveView testing](https://phoenix-live-view.hexdocs.pm/1.2.11/Phoenix.LiveViewTest.html), and [Gettext](https://gettext.hexdocs.pm/) for the server-rendered interface, behavioural tests, and localization.
