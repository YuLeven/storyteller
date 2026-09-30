# Product benchmark and interaction principles — 2026-09-30

This is a first-party desk benchmark refreshed from official product pages on 2026-09-30. It records advertised workflows, not hands-on usability findings or independent evidence of GM accuracy. The team still needs to try representative tasks in each product and record what actually feels faster, clearer, or more reliable. Product descriptions below are attributed claims, not verified feature behavior.

## Comparison set

| Product | Current public focus | Useful pattern for Storyteller | Storyteller's opportunity |
| --- | --- | --- | --- |
| [Friends & Fables](https://fables.gg/) | The current homepage presents an AI GM, campaign/world-building tools, travel, quests, inventory, maps, generated images, narration, and an integrated virtual tabletop with tactical combat and parties of up to six. It is a D&D-inspired hosted game with desktop, tablet, and mobile play. | Put immediate scene context, companions, goals, and actions together at the moment of play. Connect campaign structure and tactical play so changes feel part of one game. | Preserve a light, text-first turn loop and player-controlled D20, support non-fantasy campaigns, persist local canonical ledgers, and make every accepted state change inspectable. |
| [Craft RPGs](https://www.craftrpgs.com/about) | Craft describes a browser AI-GM platform for any system, with user-authored rules and custom character sheets, entities, maps, and worlds represented as files. Its CLI supports local/offline editing and import/export; the vendor says the model reads relevant context on demand. | Let campaigns and rule systems grow from modular pieces while keeping user-authored source material editable and portable. Explicitly written system rules can help the GM follow campaign-specific procedures. | Build genre-flexible state models from the start, while keeping mechanical checks and resource changes explicit and testable. Our local-first persistence remains a product constraint; Craft's context and accuracy claims still need play testing. |
| [Kanka](https://kanka.io/features) | Kanka advertises a configurable campaign database with around 20 entity types, optional categories, role-specific dashboards, maps with layers and pins, timelines/calendars, inventories attached to many entity types, and custom properties/formulas. | Give the table a canonical place to record people, places, possessions, currencies, and campaign-specific data, while allowing unused sections to be hidden. Its examples cover both character equipment and setting-level inventories. | Automate state capture through validated GM proposals and reduce setup work. Keep only the panels and records relevant to this campaign visible instead of turning play into database administration. |
| [LegendKeeper](https://www.legendkeeper.com/rpgs/) | LegendKeeper describes a system-agnostic map/wiki workspace with linked lore, maps and pins, collaborative boards, full-text search, tags/properties, templates, secrets, and offline support. | Keep reference material and geography connected, and give the GM a way to prepare or reveal hidden information. | Offer the useful current-scene subset directly on the player board. Add map interaction when it improves orientation or travel enough to justify the extra interface and setup. |

The products serve different styles. Friends & Fables combines AI play and virtual-tabletop features; Craft emphasizes modifiable AI games and file-based worlds; Kanka is a configurable campaign database; LegendKeeper is a linked map/wiki workspace. These product pages establish the range of advertised features, but do not establish comparative usability, reliability, or state accuracy. Storyteller's core is the human player at a shared-feeling table with a persistent AI GM: describe an action, receive a grounded response, and trust that the visible campaign record stayed coherent.

## Market notes refreshed 2026-09-30

- Friends & Fables' maker says the product continues as an easy, unlimited D&D 5e-style service, while Craft is the broader route for custom systems, worlds, models, and creator control ([maker's product-direction post](https://www.craftrpgs.com/blog/craft-a-new-approach-to-ai-rpgs)). Treat this as a product-positioning distinction, not an independent comparison of play quality.
- Craft's current public materials describe custom file types and character sheets, GM tool actions that can read or update fields, maps, world-building tools, and a visible turn-action trace. Its own framing acknowledges a tradeoff: simple defaults make play easier, while deeper control adds decisions for creators. Storyteller should keep setup approachable while making important state changes explicit, reviewable, and safely validated ([Craft overview](https://www.craftrpgs.com/about), [Craft glossary](https://www.craftrpgs.com/docs/a-glossary-of-craft-terms)).
- Kanka documents an inventory on every entry, with examples spanning character possessions, shop stock, quest rewards, and shared group loot. Its campaign dashboard can be customized, but its guide cautions that too many widgets reduce clarity and that dashboard drag-and-drop does not work on mobile. This supports Storyteller's campaign-specific panels and mobile scene shortcuts, with a small set of timely facts kept ahead of exhaustive reference data ([Kanka inventory](https://docs.kanka.io/en/latest/features/inventory.html), [dashboard guide](https://docs.kanka.io/en/latest/guides/dashboard.html)).
- LegendKeeper's public product page emphasizes linked lore, maps and pins, secrets, offline work, export, and collaboration. It remains a worldbuilding/reference comparison rather than an AI-GM turn-loop comparison. Its map-and-lore strength is a future direction only after Storyteller's current-scene orientation and continuity are dependable ([LegendKeeper overview](https://www.legendkeeper.com/)).

These are official product descriptions and vendor-stated tradeoffs. No competitor account was created, no terms were accepted, and no competitor campaign was played; this remains desk research, not hands-on usability benchmarking. The six-task comparison below is still open.

## Hands-on benchmark tasks

No competitor has been interactively tested for this refresh. When access is available, run the same tasks in each product and Storyteller, recording elapsed time, steps, blockers, and whether the result remains understandable after leaving and returning. Do not infer reliability or ease of use from marketing pages.

1. Create a small campaign and reach the first playable scene.
2. Find the current place, immediate situation, present characters, and player-owned resources without searching the whole history.
3. Describe using or exchanging an item/resource; verify the result and reason are visible and the balance persists.
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

## ChatGPT-plan media constraint

The official [Sign in with ChatGPT preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) page says image generation is unsupported in the ChatGPT-plan Responses flow, even though some general API model pages list image-generation tools. Storyteller therefore cannot promise live, per-turn scene illustrations through the existing Plus OAuth connection. Any generated illustrations need a separate supported local image-generation path or user-provided campaign art; do not silently add API billing or switch this project away from the Plus-only constraint. The text GM continues through the supported streamed Responses path.

Once a no-additional-billing image source is chosen, scene art should be attached to the relevant story beat and revealed in the same paced sequence as its narration, with a skip-to-latest control and reduced-motion support. That media-card behavior is not implemented yet; the current turn queue handles text and state events only.

## Apple's interaction guidance applied to the web app

Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) are product guidance, not a visual theme to copy. Apple says feedback should help people understand current status, available next actions, and the result of an action; its [feedback guidance](https://developer.apple.com/design/human-interface-guidelines/feedback) recommends placing routine status near the content it describes and reserving disruptive alerts for consequential problems.

- **Start with the scene.** Put the place, surroundings, people present, current action, and next choice where the player can find them without browsing admin pages.
- **Show cause and result.** Keep GM progress near the current turn. When an action changes inventory, location, or a tracked balance, show the accepted change in the same campaign story.
- **Keep the player in control.** Make pending rolls and failures legible, retain the player's action during recovery, and state why a command could not proceed.
- **Use flexible structure.** Show a vineyard's wine and cash, a dungeon's equipment, and a mystery's clues without forcing each campaign into the same rule sheet.
- **Support access and responsive use.** Maintain keyboard focus, readable contrast, meaningful labels, reduced motion, and a layout that works on a narrow screen.
- **Delight through trust.** A satisfying discovery and consistent NPC are more valuable than ornament if a resource, person, or place cannot be trusted to persist.

## Storyteller baseline and remaining gaps

The current application stores campaign-wide state and timeline events across sessions. The model receives campaign setup, bounded recent history and summaries, canonical public/private world state, inventories, places, character facts and locations, typed panel definitions, and public/private objectives. The player board displays current location and surroundings, visible people in that location, tracked campaign values, known owned items, NPC activity, public objectives grouped by status, and the chronological story. Inventory, location, and objective changes are validated operations; public projections omit GM-private records.

The data model has meaningful safeguards, but it does not eliminate model mistakes. Campaign setup stores flexible player-visible character details, and accepted in-play changes now require a public fact patch with an action-grounded reason; tests cover identity/private-write rejection, audit visibility, and later-session continuity. Post-creation inventory management remains a gap, alongside linked people and richer map navigation. Objectives are durable, but there is no broader journal or objective detail workflow yet. The current player board presents locations and known facts as structured text; it does not yet offer an interactive map. Behavioral tests should continue to check item conservation, resource arithmetic, private facts, NPC location, retry/reconnect paths, and cross-session continuity.

## Product direction

1. Keep in-world additions, transfers, and consumption within the GM-proposed turn flow so the player board remains trustworthy. Direct player writes to canonical inventory are out of scope for the single-player MVP; revisit an auditable correction request only if playtesting shows the normal action flow cannot resolve state mistakes reliably.
2. Keep the flexible player character sheet trustworthy: optional fields stay out of campaigns that do not need them, while accepted updates remain justified, public, and continuous across sessions.
3. Keep place, presence, item, objective, panel, and event state canonical. Give the GM relevant hidden context, validate proposed changes, and commit accepted deltas atomically.
4. Prioritize the current scene, clear status, accessible reading, and error recovery over decorative dashboards. Keep the browser light and LiveView-driven.
5. Run cross-session behavioral scenarios for conservation, ownership, private context, location, progression, and durable restart/resume.
6. Hands-on test representative tasks in Friends & Fables/Craft, Kanka, and LegendKeeper using only the separate fictional QA campaign. Record task steps and friction; do not change or use vineyard data for benchmarking.
7. Treat competitor claims as hypotheses until interactive task checks are possible; compare setup-to-first-turn time, state correction, cross-session continuity, and how quickly a player can find current-scene facts.

## References

- Friends & Fables, [product overview](https://fables.gg/), [Craft open-beta and product direction](https://fables.gg/patch-notes/craft-open-beta-and-credit-transfer), and [the standalone play surface announcement](https://fables.gg/blog/a-new-chapter).
- Kanka, [feature list](https://kanka.io/features) and [campaign/world overview](https://docs.kanka.io/en/latest/overview.html).
- LegendKeeper, [RPG campaign manager](https://www.legendkeeper.com/rpgs/) and [worldbuilding feature overview](https://dev.legendkeeper.com/).
- Apple, [Human Interface Guidelines: Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Design Principles](https://developer.apple.com/design/human-interface-guidelines/design-principles), and [UI Design Dos and Don'ts](https://developer.apple.com/design/tips/).
