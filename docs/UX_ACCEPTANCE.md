# UX acceptance brief

This brief defines observable acceptance for the locally hosted, single-player Storyteller MVP. It follows the committed `IMPLEMENTATION_PLAN.md`; it does not define new game mechanics. A screen is accepted when the player can understand what is happening, choose what to do, and recover without losing or duplicating campaign state.

## Campaign library

- The library lists the player's campaigns and provides clear actions to create, open/resume, and archive one. Empty and loading states explain the next available action.
- Each campaign shows enough identifying information to distinguish it from others and to choose the correct one. Opening or switching campaigns never mixes their characters, timeline, or world state.
- A campaign exposes its sessions as resumable segments of one continuous campaign history. Starting or switching sessions preserves prior turns and canonical state. The exact session creation and archive presentation remain open choices (see below).

## Create campaign

- A guided flow collects the campaign title, story premise, setting, tone, narration language, player character details, optional GM-controlled characters, starting location/date/weather, and any campaign-specific mechanics. It makes required versus optional inputs clear without inventing rules or requiring unsupported character fields.
- The player can review the assembled setup before creating the campaign. Editing or returning between steps preserves entered content; validation identifies the affected field and explains how to fix it.
- Successful creation opens the new campaign in a ready-to-play state. The chosen narration language is stored separately from the interface locale.
- Exact wizard step order, field-by-field validation, and which setup fields are required remain design choices unless specified by product decisions.

## Play screen and player agency

- The play screen presents a readable, chronological timeline that distinguishes player input, GM narration, speaker-attributed NPC dialogue, relevant GM-controlled character activity, and rolls. New completed turns appear without a full-page reload. The initial recent window is bounded; a clear, keyboard-accessible action loads preceding campaign history in chronological order until the earliest event is reached.
- NPC speech is visually attributed to its speaker. Visible activity communicates what relevant NPCs do; it does not reveal private facts, hidden motives, offstage events, or other GM-only state.
- A compact header shows current player-visible world state, including location and in-world date/time and weather where available. Configured campaign panels show their labelled, typed, unit-aware visible fields; the vineyard may use cash, wine inventory, and vine inventory. Panels must not expose private values.
- Each date, time, and weather fact has one canonical value across the GM's hidden context, the compact header, and the scene board. Legacy aliases and conflicting persisted values must not create duplicate or contradictory facts in play.
- A player can find a concise character board during the scene: current place and surroundings, immediate situation, character details they know, current companions' visible activity, and owned inventory/resources. This should answer “where am I, what is happening, what do I carry or control?” without reading the entire timeline first.
- Campaigns can model distinct carried items and consumables with stable identity, owner, quantity, unit, and any campaign-relevant safe details. Resource ledgers also support non-item values such as vineyard cash, wine stock, and vines. The same interaction works for different campaign genres without hardcoded vineyard or dungeon rules.
- A text composer lets the player submit an action or speech. Pending submission prevents accidental duplicates and makes the submitted text and resulting turn status understandable.
- The GM responds to player choices with natural consequences, preserves established facts, and returns control to the player. The UI never writes the player's actions, speech, thoughts, or choices on their behalf. It does not present a proposed state change as canonical before the application accepts it.
- Location, character presence, inventory ownership, and resource quantities are canonical persisted state. Narration alone cannot change them: accepted state deltas reference stable records, are validated, committed once with their turn, and appear in a traceable history. If a turn records multiple player movements, the final canonical place and world location agree in the player board and later GM context. Numeric campaign balances use signed deltas applied against the locked current value; text/status/date fields use typed set operations. Each resource history entry shows the field, before and after values, operation, unit, and grounded reason. A read-only account review creates no balance change.
- Long campaigns retain separate public and GM-private continuity summaries. A bounded recent-event window keeps each GM request practical, while older events remain in durable storage and are available to the player through cursor-paginated campaign history. Pages use immutable event sequences, appear exactly once in chronological order, and remain loaded during live updates. Older-history loading does not announce past events as new story; only a small recent portion is in the polite live region. Summaries support retrieval but never replace the authoritative item, location, character, and resource records. Private continuity must never appear in player projections.
- Narrow layouts keep the timeline, composer, die when relevant, world header, and access to campaign panels usable without horizontal page overflow. A compact sticky in-page navigation provides a direct keyboard-accessible jump to the active turn composer, campaign story, current scene and place, and inventory, plus objectives and tracked resources when those public sections have content. Anchor targets receive focus with a visible indicator and clear the sticky bar. Nested people and objective rows must retain readable contrast against dark cards; a 370px visual spot check covers translucent amber/white surfaces, while formal contrast and assistive-technology review remains open. The precise panel arrangement at each breakpoint remains open.

## Player-click D20 flow

- If an uncertain, consequential player action needs a roll, the timeline states what is being tested and the difficulty or target before asking for the player's roll. Ordinary actions do not trigger a roll merely to add activity.
- The player initiates the roll with an explicit D20 click. The interface clearly indicates when a roll is awaited, accepted, and resolved; the recorded result is visible in the turn history. The server-generated result is applied exactly once.
- The GM does not silently roll for a player-controlled character. The current MVP lets the player initiate their own D20 result; add a distinct, auditable GM roll only if a campaign's rules require it.
- The exact dice presentation, animation, and any campaign-specific interpretation of targets remain open choices; the interface must not imply mechanics that the campaign has not defined.

## Progress, failure, and reconnect

- While a GM response is in progress, show a clear pending/progress state and keep the player from submitting a duplicate action. Do not imply that a turn is complete before the response is validated and committed.
- On timeout, invalid response, or other recoverable failure, explain that resolution did not complete, preserve the prior canonical state, and offer a clear retry path. Retrying does not duplicate the action, event, roll, or state change.
- If a turn is waiting for a player roll, a refresh or reconnect restores that same pending turn and roll request. If a turn completed, reconnect restores the completed timeline and current state. The player should not have to infer whether an action was lost or applied twice.
- When account usage prevents a GM request, pause play with an actionable explanation and preserve turn state. Do not silently switch to paid API usage.

## Localization and accessibility

- English, Spanish, and French are available across campaign setup and play, including navigation, labels, validation and recovery messages, dates, numbers, dice labels, and campaign-panel chrome. The initial UI locale is English, and the global selector changes the persisted interface locale.
- Changing the UI locale updates interface text and formatting without translating or rewriting stored turns. GM narration follows the campaign's narration language; user-authored names, story text, and custom field labels remain as entered. Untranslated custom content has a clear fallback.
- All actions, including form navigation, campaign/session selection, turn submission, and the D20 click, are keyboard operable with a visible focus indicator. Focus moves predictably after navigation, validation errors, and turn updates.
- New story entries are exposed through a polite, additions-only live region so assistive technology can announce appended events without rereading the full campaign timeline.
- Text and controls remain readable at narrow viewport sizes and at increased text zoom. Status/progress, roll result, errors, and speaker identity are not conveyed by color alone; semantic labels are available to assistive technology. Check contrast, heading order, and announced dynamic updates in each locale.
- The plan does not specify a formal WCAG conformance level or locale-specific defaults; confirm those product choices rather than claiming an unverified level.

## QA boundaries

- **Manual gameplay QA:** Exercise the end-to-end experience in a fictional, explicitly separate QA campaign. Cover campaign creation/switching, multiple sessions and resume, narration/dialogue/activity, a player-click roll, visible panel updates, narrow-screen use, and recovery from a pending or failed turn. Never use, overwrite, or import the vineyard campaign for feature or regression testing.
- **Automated tests:** Use a separate test database, isolated fixtures, a fake GM provider, and a fixed roll source. Assert observable behavior and durable state for campaign isolation, session continuity, turn statuses/idempotency, visibility, D20 flow, locale changes, failure/reconnect recovery, and loading multi-page campaign history without duplicates or losing loaded pages during refresh. Normal automated tests make no live AI calls. Keep the opt-in live-provider smoke check separate from the default suite.
- **Story quality review:** Human-review scenario fixtures for natural consequences, restrained escalation, consistent facts, independent NPC agency, and preservation of player agency. Do not use exact-prose snapshots as the quality bar.
- **Continuity review:** Across multiple sessions, test no unsupported item gain/loss, no accidental duplicate or wrong-owner transfer, no uncommitted location change, and no NPC appearing in an unestablished place. Confirm private facts are present in the GM's prompt and absent from every player-visible projection.
- **Product benchmark:** Compare the player board, inventory model, location/context navigation, secrets, and campaign memory against AI-native tools and system-agnostic campaign managers. Record what is public product documentation, what was hands-on tested, and what is a Storyteller design decision. Use the comparison to improve core tasks, not to chase feature count.
- **Interaction principles:** Apply purpose, player agency, responsibility, familiar mental models, clear feedback, responsive flexibility, simplicity, craft, and delight. Make accepted changes understandable and reversible where safe; keep settings and state-management details close to the content they affect.

## Open design choices to resolve

- Confirm whether sessions are always continuous resumable segments or whether campaign branches are desired; the plan currently selects continuous history.
- Decide campaign-library treatment of archived campaigns and which setup fields are required, optional, or editable after creation.
- Decide how inventory entries are created or edited, which safe item fields are supported, and whether any campaign modes need weight/equipment rules. Do not invent mechanics that a campaign has not chosen.
- Decide how known locations and movement are represented for freeform and map-based campaigns, including when a location is hidden from the player.
- Review whether panel field definitions are player-configurable, which safe field types and visibility choices are offered, and what edit path is supported. Do not add arbitrary executable formulas.
- Confirm any formal accessibility conformance target. The UI-locale default, global selector, and separation from the campaign narration language are set.
- Confirm the responsive panel arrangement and the visual style of timeline event types and D20 presentation. Do not change the specified roll ownership or invent campaign mechanics to settle these visual choices.
- Evaluate whether the player board keeps current scene, inventory, and resources findable at both wide and narrow sizes, including assistive-technology navigation. The visual theme is subordinate to a reliable play surface.
