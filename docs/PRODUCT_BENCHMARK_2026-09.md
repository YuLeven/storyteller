# Product benchmark and interaction principles — 2026-09-30

This is a first-party desk benchmark refreshed from official product pages on 2026-09-30. It records advertised workflows, not hands-on usability findings or independent evidence of GM accuracy. The team still needs to try representative tasks in each product and record what actually feels faster, clearer, or more reliable.

## Comparison set

| Product | Current public focus | Useful pattern for Storyteller | Storyteller's opportunity |
| --- | --- | --- | --- |
| [Friends & Fables](https://fables.gg/) | Hosted AI GM, creator worlds, lore, maps, travel, inventory, quests, and integrated virtual-tabletop play. The current site highlights location, nearby NPCs, goals, dice, and combat. | Put immediate scene context, companions, goals, and actions together at the moment of play. Keep the model grounded in a structured campaign world. | Preserve the player's text-first turn and self-rolled D20, support non-fantasy campaigns, persist local canonical ledgers, and make every accepted state change inspectable. |
| [Craft RPGs](https://craftrpgs.com/) | Friends & Fables' August 2026 open-beta announcement describes Craft as a separate AI RPG platform for any game system, with highly customizable GM prompts and a large context window. F&F says it is refocusing its own product as a more manageable 5e-like experience, with future work on memory, storytelling, and state updates. These are vendor claims, not comparative test results. | General-purpose campaign play benefits from customizable rules and a GM whose behavior can be corrected. The separation of products also demonstrates the cost of retrofitting broad flexibility into a tightly coupled rules engine. | Build genre-flexible state models from the start, while keeping mechanical checks and resource changes explicit and testable. Local ownership and a user's existing eligible ChatGPT plan are additional product constraints. |
| [Kanka](https://kanka.io/features) | Campaign management with configurable entity categories, linked characters and places, inventories, abilities with charges, custom properties, calendars, timelines, maps, role visibility, and dashboard widgets. | Let players and GMs find structured campaign details without maintaining them in disconnected notes. The inventory examples span character possessions, shops, and quest rewards; property widgets can adapt the interface to a setting. | Automate state capture through validated GM proposals and reduce setup work. Keep only the panels and records relevant to this campaign visible instead of presenting a large admin database during every turn. |
| [LegendKeeper](https://legendkeeper.com/rpgs/) | Map- and wiki-first worldbuilding: linked pages, nested maps and pins, journeys, secrets, templates, collaborative editing, offline work, and exports. | Keep lore and geography connected; make it possible to hide a map pin or secret until the story reveals it. | Offer the useful current-scene subset directly on the player board. A map should add orientation or travel value, not become required setup for every campaign. |

The products serve different styles. Friends & Fables and Craft are AI-native hosted games; Kanka is a modular campaign database; LegendKeeper is a linked map/wiki workspace. Storyteller's core is the human player at a shared-feeling table with a persistent AI GM: describe an action, receive a grounded response, and trust that the visible campaign record stayed coherent.

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

## References

- Friends & Fables, [product overview](https://fables.gg/), [Craft open-beta and product direction](https://fables.gg/patch-notes/craft-open-beta-and-credit-transfer), and [the standalone play surface announcement](https://fables.gg/blog/a-new-chapter).
- Kanka, [feature list](https://kanka.io/features) and [campaign/world overview](https://docs.kanka.io/en/latest/overview.html).
- LegendKeeper, [RPG campaign manager](https://www.legendkeeper.com/rpgs/) and [worldbuilding feature overview](https://dev.legendkeeper.com/).
- Apple, [Human Interface Guidelines: Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Design Principles](https://developer.apple.com/design/human-interface-guidelines/design-principles), and [UI Design Dos and Don'ts](https://developer.apple.com/design/tips/).
