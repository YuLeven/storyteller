# Product benchmark and interaction principles — refreshed 2026-09-30

This is a first-party desk benchmark checked against official product and documentation pages on 2026-09-30. It describes what vendors currently advertise and separates dated roadmap statements from current feature lists. It is not hands-on usability research or independent evidence of GM quality, reliability, or state accuracy. No competitor account was created, terms accepted, or campaign played; no product is ranked.

## Comparison set

| Product | Current advertised focus | Useful pattern for Storyteller | Product implication |
| --- | --- | --- | --- |
| [Friends & Fables](https://fables.gg/) | Its homepage advertises an AI GM, world-building tools, tactical 5e combat, quests, lore, travel, inventory, maps, generated images, text-to-speech, and parties of up to six. An Aug. 5, 2026 announcement says F&F remains available with a narrowed 5e-like direction and that its planned focus is improving memory, storytelling, and state updates; Craft is the broader customizable product ([announcement](https://fables.gg/patch-notes/craft-open-beta-and-credit-transfer)). | Keep immediate scene context and actions close to play, and judge continuity by what remains consistent across turns. | Storyteller already keeps state changes in canonical panels and limits the transcript to player, GM, and character communication. Make results and provenance easy to inspect without returning system notices to the conversation. |
| [Craft](https://www.craftrpgs.com/about) | Craft advertises solo browser play across user-defined systems; file-based worlds with custom types, fields, and layouts; a configurable AI GM; maps and generated media; project import/export; and a CLI for local editing. The product page lists free daily usage and paid tiers, so its hosted usage model is not directly comparable to Storyteller's local ChatGPT-plan connection. | Give campaign authors expressive rules and structures, and make their world data portable. | Preserve genre flexibility and campaign ownership while keeping routine play simple. Use typed, validated game state and visible recovery rather than exposing implementation traces as extra chat. |
| [Kanka](https://kanka.io/features) | Kanka advertises roughly 20 optional entry categories, role-aware customizable dashboards, inventories on every entry, flexible properties/formulas, quests and journals, calendars/timelines, and maps with visibility-controlled pins. Its dashboard guide warns that excessive widgets reduce clarity and that drag-and-drop arrangement does not work on mobile ([dashboard guide](https://docs.kanka.io/en/latest/guides/dashboard.html)). | Model a campaign's people, places, objects, and genre-specific resources without requiring every campaign to use every category. | Keep the active play board small and scene-led. Let optional campaign records grow behind deliberate navigation instead of making every possible field part of the turn. |
| [LegendKeeper](https://www.legendkeeper.com/rpgs/) | LegendKeeper advertises a system-agnostic linked wiki, maps and pins, boards, search, templates, permissions/secrets, export, and offline editing. Its feature page describes offline changes as browser-local until they sync and lists mobile support under planned features ([feature list](https://www.legendkeeper.com/features/)). | Connect a place on the map with its lore and give the GM precise control over what is revealed. | Add spatial orientation only when it helps a player decide where to go; retain the quick text scene card and ensure secret places never leak through map labels or pins. |

These products serve different styles: Friends & Fables and Craft advertise AI-led play; Kanka is a configurable campaign database; LegendKeeper is a worldbuilding and map workspace. Vendor pages establish advertised features and positioning, not how well a workflow performs in real play. Craft's customizability may remove limits for a builder while increasing setup decisions for a casual player; Storyteller should test both sides of that tradeoff instead of assuming more controls are automatically better.

## Workflow comparison (public evidence, checked 2026-09-30)

This is a workflow comparison from official public pages, product documentation, and public Craft project examples. I did not create accounts, accept terms, or play an authenticated session. Public descriptions help identify product patterns, but they do not establish how quickly a real player completes a task or how reliably an AI preserves canon. “Not documented in the reviewed sources” means exactly that; it is not a claim that the product lacks the feature.

| Product | Setup and arrival at play | Play board and inventory | Continuity and privacy | Evidence boundary |
| --- | --- | --- | --- | --- |
| **Friends & Fables** | Its public GM-tools page exposes optional generation controls for characters, places, classes, races, and items, plus custom instructions. Its homepage describes creating or exploring worlds and starting AI-GM campaigns, but does not publish a complete setup walkthrough. ([GM tools](https://fables.gg/worlds/world-1-l2xiacv1gw5f/gamemaster), [product overview](https://fables.gg/)) | The homepage advertises an AI GM, tactical combat, maps, inventory, and character/world tools. It does not explain how the inventory is edited, how accepted deltas are reviewed, or what the active play board prioritizes. | The homepage advertises “advanced memory and customization.” The public pages reviewed do not specify what is canonical state versus model memory, how hidden GM context is scoped, or whether players can inspect a change history. | Treat the memory and inventory claims as product positioning, not demonstrated continuity. No authenticated campaign or public interactive gameplay walkthrough was tested. |
| **Craft** | A project can hold multiple games. A **Game Start** defines a starting location, selectable characters, and opening story; an optional **Prelude** can present choices and character creation before the first GM message. ([Craft glossary](https://www.craftrpgs.com/docs/a-glossary-of-craft-terms)) | The glossary documents a collapsible Actions section in game chat and a separate OOC Assistant tab. File types define custom fields/layouts; public project examples show equipment inventories and campaign-state/log structures. These examples illustrate author-created models, not a universal inventory UI. ([V5 public project manual](https://www.craftrpgs.com/discover/projects/v5-vampire-the-masquerade?view=builder-manual), [Morioh public project manual](https://www.craftrpgs.com/discover/projects/morioh-1999?view=builder-manual)) | File-level context visibility controls what the GM loads; instructions can be always loaded or triggered, and OOC assistant memory is described as separate from campaign memory. A public sample also labels a GM-only lore area. These sources describe AI context and authoring patterns; they do not establish a full player-side permission model or prove leakage resistance. ([glossary](https://www.craftrpgs.com/docs/a-glossary-of-craft-terms), [V5 manual](https://www.craftrpgs.com/discover/projects/v5-vampire-the-masquerade?view=builder-manual)) | Public project manuals were readable without signing in and provide concrete setup/data examples. They are creator-authored references, not an independently tested game flow. The V5 manual reports an update on Sep. 8, 2026; the StoryRig 2d6 example reports Aug. 14, 2026. |
| **Kanka** | Create a campaign from the campaign switcher, then configure campaign fields and privacy defaults. A new campaign dashboard starts nearly empty and is populated by adding widgets; the docs caution that adding too much information reduces clarity and can lengthen page loads. ([campaign settings](https://docs.kanka.io/en/latest/features/campaigns/campaign-settings.html), [dashboard guide](https://docs.kanka.io/en/latest/guides/dashboard.html)) | Inventory is available on any entry. An item may be free-named or linked to an existing entry, items can be grouped by position, and positions can collapse. This supports different owners/resources, but the cited guide describes campaign records rather than a live turn-by-turn game board. ([inventory guide](https://docs.kanka.io/en/latest/features/inventory.html)) | Admin-only entries and visibility-marked attached elements can be hidden; visibility chains through related inventory and other linked records. Entry change logs can be enabled, and admins can preview the campaign as a non-admin member. This is a concrete privacy-QA pattern; it is a permissions system, not evidence about AI prompt construction. ([secrets guide](https://docs.kanka.io/en/latest/guides/secrets.html), [visibility rules](https://docs.kanka.io/en/latest/advanced/visibility.html), [test permissions](https://docs.kanka.io/en/latest/guides/testing-permissions.html)) | These first-party docs spell out configuration and permission workflows. They do not demonstrate an AI GM or cross-turn narrative continuity. |
| **LegendKeeper** | Official guides describe building a private project with pages and maps; a map starter pack and creating pages from map pins are available. The reviewed sources do not describe a guided campaign-to-first-turn setup. ([maps](https://www.legendkeeper.com/features-maps/), [feature list](https://www.legendkeeper.com/features/)) | The map can link to wiki articles, use customizable pins and nested maps, and be shared with selected audiences. Collaboration pages describe players editing permitted pages and navigating shared maps. The reviewed sources do not describe a conversational GM play board or a purpose-built quantity/ownership inventory flow. ([maps](https://www.legendkeeper.com/features-maps/), [collaboration](https://www.legendkeeper.com/features-collaboration/)) | The feature list advertises private-by-default projects, granular permissions/secrets, and hidden map pins; maps may be shared or kept private. The pages reviewed do not document AI continuity or structured turn commits. ([feature list](https://www.legendkeeper.com/features/)) | This is useful evidence for spatial reference and worldbuilding boundaries, not a like-for-like AI campaign workflow. The feature list labels the product Beta and distinguishes current from planned features. |

### Decisions for Storyteller

1. **Get to a playable premise with a short guided setup.** Ask for premise and narration language, then the player's character and a first scene. Offer starting NPCs, extra world state, and genre-specific resource panels as optional next steps. Keep a blank/custom path. Craft's Game Start concept and Friends & Fables' stated low-friction goal support landing the player inside a particular situation; neither public source establishes the ideal number of setup steps, so validate this flow with first-play tasks.
2. **Make the play board answer “where am I, what is happening, and what can I do?”** Keep the current scene and visible people/state adjacent to the conversation. Keep optional campaign records in secondary navigation. Kanka's dashboard documentation explicitly warns that too many widgets reduce clarity; Craft's separate OOC assistant and collapsible action trace show ways to keep operational detail out of ordinary in-character conversation.
3. **Keep inventories flexible and concrete.** Use campaign-defined resources/items with quantity, unit, and owner where relevant; a vineyard may track cash and wine while a dungeon tracks carried equipment. Show current public totals first and a collapsed receipt for accepted add/transfer/update changes, with a concise public reason and in-world time. Kanka's named-or-linked items and Craft's flexible file types are patterns for accommodating different campaign schemas; Storyteller should keep turn outcomes and current owned state connected.
4. **Treat canon and privacy as data boundaries.** Persist validated world state and event history separately from prose summaries; give the GM only relevant context for the current turn, and never let hidden facts/reasons enter player-facing messages or projections. Kanka's visibility chaining and “view as member” workflow suggest an explicit player-view privacy check. Craft's context visibility is useful for relevance management but should not be mistaken for a proven access-control guarantee.
5. **Benchmark what the sources cannot tell us.** In a separate fictional campaign, time a new player reaching the first scene, finding current facts, reviewing an item change, and resuming after a day. Record friction and state comprehension. Do not convert vendor feature claims or public project examples into a comparative usability score.

## Storyteller's documented baseline

The current checkpoint describes a locally hosted Phoenix LiveView game with persistent campaigns and sessions, a player-controlled D20, streamed ChatGPT-plan GM responses, bounded public/private memory, and canonical campaign state. The player board shows in-world date/time/weather, current place and surroundings, people present, tracked flexible resources, owned items, objectives, and character details. Inventory, location, character, objective, continuity, and resource changes are validated and durable across sessions. The story is paced, independently scrollable, and reserved for the player's action, GM narration, direct character dialogue, and rolls; structured state changes update their panels with restrained feedback. See the [implementation checkpoint](CHECKPOINT_2026-09-30.md), [feature log](FEATURE_LOG.md), and [UX acceptance brief](UX_ACCEPTANCE.md).

Documented gaps include an interactive campaign map, optional in-story illustrations that do not add API billing, and full keyboard/screen-reader review. Campaign backup and restore are implemented behind a collapsed secondary disclosure so they do not compete with starting or resuming play. The interface has campaign-specific panels and data, but no benchmark evidence establishes how quickly a new player can configure a genre, reach play, correct a mistaken fact, or resume after a long gap. These are product hypotheses to measure, not competitor shortcomings.

## Actionable opportunities

The Apple-inspired interaction notes below emphasize scene-first orientation, feedback beside the content it describes, proportionate interruption, player control, flexible structure, accessible use, and trust. The active order follows the MVP triage gate in `IMPLEMENTATION_PLAN.md`: improve the actual play loop first, based on observed player friction and state-trust failures.

1. **Play a complete session and repair what gets in the way.** In a separate fictional campaign, test a GM-led opening, one ordinary action, a question/look nudge, a player D20, a time-passage nudge, a tracked item or resource change, and a return after leaving the page. Record where the player hesitates, loses context, or cannot tell what happened. Fix turn pacing, action retention, current-scene clarity, recovery, or continuity before adding secondary capabilities. **Check:** the player can state where they are, what just changed, and the next available choice without searching through administrative UI; all accepted state is still correct after resume.
2. **Verify the existing state receipts during play.** Tracked resources, inventory, places, and characters now have collapsed “Last changed” details with accepted before/after values, a safe reason when available, and in-world time, sourced from public events. Keep receipts by the relevant panel and out of the story feed. Apple recommends routine status near the content it describes and reserves interruption for consequential problems ([HIG: Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)); use the normal turn tasks to learn whether these receipts help the player trust a change or add noise.
3. **Make first play approachable when task evidence shows setup friction.** Offer editable examples such as dungeon exploration, vineyard stewardship, and mystery investigation only if a blank campaign proves hard to configure. Keep suggestions optional and removable. Kanka's modular categories show the breadth a campaign database can support, while its dashboard guide warns that excess widgets harm clarity; Craft offers deeper authoring with more setup decisions. **Check:** compare time, errors, and help needed to reach the first scene before committing to presets.
4. **Add a visibility-aware map after text play is dependable.** Start with a player-supplied map and current-place marker; show destinations or NPC pins only when canonical records exist and are public. Kanka and LegendKeeper advertise linked maps and visibility controls. **Check:** ensure a map improves an actual travel decision and never exposes a GM-private location.
5. **Bring optional art into the paced story only after the core turn reads well.** Prefer player-supplied art before considering a local generation integration; keep it optional, attached to its narration beat, and outside the next-action path. The ChatGPT-plan route does not provide image generation, so do not imply or silently bill for it.

Campaign restore is available in a collapsed library section even when there are no campaigns; export is in a collapsed campaign-detail section. No further backup feature work is in the active MVP queue. Maps and art remain later opportunities, not blockers to excellent text play. Do not assign comparative usability scores until hands-on tasks have been run.

## Source freshness and limits

Official pages were accessed on 2026-09-30. The Friends & Fables product-direction statement is dated Aug. 5, 2026; its homepage remains a current advertised-feature list, so the two are kept distinct above. Craft's current About page and patch-note index (latest entry checked: Sep. 29, 2026), Kanka's feature and 1.0 documentation pages, LegendKeeper's current feature list, and Apple's HIG feedback page were checked during this refresh. LegendKeeper labels its feature status as Open Beta and separates planned from current features. Product pages and pricing can change; revisit them before basing implementation or cost decisions on them. Every feature statement is vendor-authored, and none confirms usability, availability for this user, or behavior under long-running play.

## Hands-on benchmark tasks

No competitor has been interactively tested for this refresh. When access is available, run the same tasks in each product and Storyteller, recording elapsed time, steps, blockers, and whether the result remains understandable after leaving and returning. Do not infer reliability or ease of use from marketing pages.

1. Create a small campaign and reach the first playable scene.
2. Find the current place, immediate situation, present characters, and player-owned resources without searching the whole history.
3. Describe using or exchanging an item/resource; verify the result and reason are reviewable from the relevant panel, the conversation stays direct, and the balance persists.
4. Continue in a later session and confirm the same campaign state and history remain available.
5. Recover from a failed response without losing or duplicating the submitted action.
6. Locate a GM-only fact during preparation and verify the player surface does not reveal it.

Friends & Fables/Craft represent AI-led play and authored campaign systems; Kanka/LegendKeeper represent structured campaign reference and worldbuilding. Some tasks will not map to every product: record “not applicable” with the product boundary instead of forcing a misleading score. No product should be ranked until the tasks have actually been performed.

## Local response baseline

On 2026-09-30, five read-only `curl` GETs per route to the running WSL development server returned HTTP 200. Request `time_total` was:

| Route | Median | Observed range |
| --- | ---: | ---: |
| Campaign library (`/`) | 0.734 s | 0.728–0.781 s |
| Amber Orchard campaign detail (`/campaigns/34`) | 0.736 s | 0.728–0.745 s |
| Amber Orchard play session (`/campaigns/34/sessions/35`) | 0.758 s | 0.738–1.010 s |

This is an initial developer-machine response baseline, not a production performance claim or acceptance threshold. The measurements include localhost forwarding between Windows and WSL. All requests were reads against the fictional QA campaign; no action or campaign state was changed. Profile the request path before attributing the latency or setting a budget.

### Recheck at commit `7314a7a`

A second five-request read-only sample against the same WSL server and fictional QA campaign returned HTTP 200 for all 15 requests:

| Route | Median | Observed range |
| --- | ---: | ---: |
| Campaign library (`/`) | 0.585 s | 0.579–0.590 s |
| Amber Orchard campaign detail (`/campaigns/34`) | 0.590 s | 0.567–0.595 s |
| Amber Orchard play session (`/campaigns/34/sessions/35`) | 0.593 s | 0.586–0.602 s |

This confirms the routes remained responsive in that local sample; it is not a production SLA or a performance comparison under concurrent load. It was taken before the next continuity and play-flow changes, so repeat after those changes for a comparable post-change baseline.

### Recheck after continuity, turn-pacing, and board-layout changes (2026-09-30)

Five read-only `fetch` GETs per route to the same WSL development server returned HTTP 200 for all 15 requests:

| Route | Median | Observed range |
| --- | ---: | ---: |
| Campaign library (`/`) | 0.645 s | 0.625–0.658 s |
| Amber Orchard campaign detail (`/campaigns/34`) | 0.624 s | 0.618–0.650 s |
| Amber Orchard play session (`/campaigns/34/sessions/35`) | 0.665 s | 0.635–0.990 s |

This is a small localhost sample including Windows-to-WSL forwarding, not a production target. It changed no campaign state and made no GM/provider calls. The previous and current medians are close enough to keep profiling as a future task rather than infer a meaningful performance regression.

### 12-request Windows localhost recheck (2026-09-30)

One warm-up and 12 timed, sequential GETs per route through a reused Windows `HttpClient` returned HTTP 200 for every request:

| Route | Median | Nearest-rank p95 | Observed range |
| --- | ---: | ---: | ---: |
| Campaign library (`/`) | 0.588 s | 1.020 s | 0.583–1.020 s |
| Amber Orchard campaign detail (`/campaigns/34`) | 0.586 s | 1.013 s | 0.583–1.013 s |
| Amber Orchard play session (`/campaigns/34/sessions/35`) | 0.590 s | 0.593 s | 0.529–0.593 s |

This sample is within the provisional local median <0.75 s and p95 <1.25 s gate above. It includes localhost/Windows-to-WSL forwarding and occasional long-tail requests; it is not a production-load result. All requests were read-only against the fictional QA campaign. No turn or provider request occurred.

### Concurrent local smoke recheck (2026-09-30)

The same three routes were checked with two warm-up requests followed by 12 timed sequential requests per route, and with 12 timed requests per route in three batches of four. Every request in the sequential and repeated concurrency runs returned HTTP 200. Sequential medians/p95s were 0.670/0.680 s for `/`, 0.672/0.683 s for `/campaigns/34`, and 0.675/0.679 s for `/campaigns/34/sessions/35`. Under concurrency four, medians were approximately 1.074, 1.078, and 1.078 s respectively; p95s were 1.573, 1.089, and 1.089 s. An initial one-off concurrency sample returned one HTTP 500 on `/`, which was not reproduced in subsequent sequential or concurrent runs. This small localhost smoke check is not production-load evidence and does not establish stability; investigate the transient response before treating the concurrency result as an acceptance baseline. Requests were read-only against the fictional QA campaign and made no provider calls.

## ChatGPT-plan media constraint

The official [Sign in with ChatGPT preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) page says image generation is unsupported in the ChatGPT-plan Responses flow, even though some general API model pages list image-generation tools. Storyteller therefore cannot promise live, per-turn scene illustrations through the existing Plus OAuth connection. Any generated illustrations need a separate supported local image-generation path or user-provided campaign art; do not silently add API billing or switch this project away from the Plus-only constraint. The text GM continues through the supported streamed Responses path.

Once a no-additional-billing image source is chosen, scene art should be attached to the relevant story beat and revealed in the same paced sequence as its narration, with a skip-to-latest control and reduced-motion support. That media-card behavior is not implemented yet; the current turn queue handles text and state events only.

## Apple's interaction guidance applied to the web app

Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) are product guidance, not a visual theme to copy. Apple says feedback should help people understand current status, available next actions, and the result of an action; its [feedback guidance](https://developer.apple.com/design/human-interface-guidelines/feedback) recommends placing routine status near the content it describes and reserving disruptive alerts for consequential problems.

- **Start with the scene.** Put the place, surroundings, people present, current action, and next choice where the player can find them without browsing admin pages.
- **Show cause and result.** Keep GM progress near the current turn. When an action changes inventory, location, or a tracked balance, update its canonical panel and make the accepted result reviewable there; keep the story for player, GM, and character communication.
- **Keep the player in control.** Make pending rolls and failures legible, retain the player's action during recovery, and state why a command could not proceed.
- **Use flexible structure.** Show a vineyard's wine and cash, a dungeon's equipment, and a mystery's clues without forcing each campaign into the same rule sheet.
- **Support access and responsive use.** Maintain keyboard focus, readable contrast, meaningful labels, reduced motion, and a layout that works on a narrow screen.
- **Delight through trust.** A satisfying discovery and consistent NPC are more valuable than ornament if a resource, person, or place cannot be trusted to persist.

## Continuity and remaining gaps

The structured ledgers reduce accidental drift, but do not eliminate model mistakes. The owner-facing goal is for players to trust canonical state over a long-running campaign. Tests cover item conservation, resource arithmetic, private facts, NPC location, retry/reconnect paths, and cross-session continuity; manual play still needs to establish whether the information is clear and correction paths are comfortable. Tracked public resources, inventory, places, and characters now have collapsed panel-level receipts with accepted before/after state, a safe reason where available, and in-world time. Campaign setup corrections have durable before/after history and a reason, while direct correction receipts for other canonical state remain open. The application also lacks an interactive campaign map and a broader journal/objective detail workflow. Behavioral tests and hands-on benchmark tasks are both needed; neither alone establishes overall campaign quality.

## Product direction

1. Keep in-world additions, transfers, and consumption within the GM-proposed turn flow so the player board remains trustworthy. Direct player writes to canonical inventory are out of scope for the single-player MVP; revisit an auditable correction request only if playtesting shows the normal action flow cannot resolve state mistakes reliably.
2. Keep the flexible player character sheet trustworthy: optional fields stay out of campaigns that do not need them, while accepted updates remain justified, public, and continuous across sessions.
3. Keep place, presence, item, objective, panel, and event state canonical. Give the GM relevant hidden context, validate proposed changes, and commit accepted deltas atomically.
4. Prioritize the current scene, clear status, accessible reading, and error recovery over decorative dashboards. Keep the browser light and LiveView-driven.
5. Run cross-session behavioral scenarios for conservation, ownership, private context, location, progression, and durable restart/resume.
6. Hands-on test representative tasks in Friends & Fables/Craft, Kanka, and LegendKeeper using only the separate fictional QA campaign. Record task steps and friction; do not change or use vineyard data for benchmarking.
7. Treat competitor claims as hypotheses until interactive task checks are possible; compare setup-to-first-turn time, state correction, cross-session continuity, and how quickly a player can find current-scene facts.

## References

- Friends & Fables, [current product overview](https://fables.gg/) and [Aug. 5, 2026 Craft open-beta and Friends & Fables direction](https://fables.gg/patch-notes/craft-open-beta-and-credit-transfer).
- Craft, [current About page](https://www.craftrpgs.com/about), [latest patch notes](https://www.craftrpgs.com/patch-notes), [Craft Data Format and CLI patch notes](https://www.craftrpgs.com/patch-notes/patch-notes-b0-24-craft-cli-cdf-v2), and [GM action glossary](https://www.craftrpgs.com/docs/a-glossary-of-craft-terms).
- Kanka, [feature list](https://kanka.io/features), [inventory guide](https://docs.kanka.io/en/latest/features/inventory.html), and [dashboard guide](https://docs.kanka.io/en/latest/guides/dashboard.html).
- LegendKeeper, [RPG campaign manager](https://www.legendkeeper.com/rpgs/) and [current feature list, including offline and planned-feature notes](https://www.legendkeeper.com/features/).
- Apple, [Human Interface Guidelines: Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Design Principles](https://developer.apple.com/design/human-interface-guidelines/design-principles), and [UI Design Dos and Don'ts](https://developer.apple.com/design/tips/).
