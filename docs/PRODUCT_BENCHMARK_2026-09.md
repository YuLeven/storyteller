# Product benchmark and interaction principles — 2026-09-29

This is an initial desk review of public product documentation, not a hands-on usability comparison. The pages below describe vendor-reported capabilities; they do not establish the quality or accuracy of a feature in real play. Revisit the comparison during QA, and record which flows have actually been tested.

## Comparison set

| Product | Publicly described focus | Useful pattern for Storyteller | Storyteller's opportunity |
| --- | --- | --- | --- |
| [Friends & Fables](https://fables.gg/) | AI Game Master, world-building tools, lore, travel, inventory, maps, and tactical D&D 5e play in one hosted experience. Its about page says the campaign engine tracks stats, takes notes, and generates content. | Keep play, campaign context, tracked things, and GM response together. Make custom world details available to the GM without turning every action into prompt writing. | Preserve system- and setting-flexible play (including non-fantasy campaigns such as a vineyard), local ownership, explicit player dice, and state changes the player can inspect. The product page's “advanced memory” claim is not independent evidence of continuity quality. |
| [Kanka](https://docs.kanka.io/en/latest/overview.html) | A system-agnostic campaign/world manager with configurable categories and connected characters, locations, events, calendars, maps, relations, and secrets. | Use linked entities and recognizable categories so players can move from a scene or log entry to the relevant person, place, or resource. Track a character's place and relationships as data. | Reduce manual upkeep by having the GM propose state changes during play, then validate and record them. Keep the source of truth durable and the public/GM-private boundary explicit. |
| [LegendKeeper](https://www.legendkeeper.com/features/) | System-agnostic worldbuilding with linked wiki pages, maps and pins, secrets/permissions, timelines, and boards. | Make geography, lore, and events navigable together; let private information remain private until the GM reveals it. | Present only the details useful to the current player scene. Keep an at-a-glance character board and a chronological play log, rather than requiring a player to browse a large prep wiki. |

These products serve different play styles: an AI-native, D&D-oriented integrated platform; a flexible campaign database; and a map/wiki-first worldbuilding tool. Storyteller should combine the most useful parts of those patterns around its own core loop: describe an action, receive a consequential response, and trust that the campaign state stayed coherent.

## Apple's published interaction principles applied to this web app

Apple's [design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles) are useful product guidance, not a visual style to copy. Translate them into these checks:

- **Purpose and simplicity:** Put the active scene, the player's character, and the next meaningful action first. Keep inventory, relationships, and world facts findable without giving every campaign an irrelevant rules dashboard.
- **Agency and responsibility:** The player owns their character's decisions and roll; the GM suggests consequences. Tell the player what is pending, what changed, what remained canon, and how to recover from a failed turn.
- **Familiarity and feedback:** Use recognizable terms such as character, location, inventory, and session. Show a clear, accessible status when a turn is saved, waiting for a roll, resolved, or failed.
- **Flexibility:** Support keyboard, touch, narrow screens, zoom, English, Spanish, and French. Let each campaign choose suitable safe inventory/resource fields.
- **Craft and delight:** Make reading a scene comfortable and expressive. Delight comes from continuity, useful discoveries, understandable consequences, and confidence in the record, not ornament alone.

Apple also advises fitting content to the device without horizontal scrolling, keeping touch targets usable, and maintaining contrast and readable text in its [UI design tips](https://developer.apple.com/design/tips/). These are practical responsive and accessibility checks for the tabletop board.

## Current Storyteller baseline and gap

The current play flow already sends the GM campaign setup, separate public and private world maps, separate continuity summaries, all campaign characters and their public/private fact maps, typed campaign panel definitions and values, and the latest 40 events across sessions. The player projection filters GM-private character facts and panel fields. Accepted panel changes are validated for their field type and committed with audit events.

The information model still has important gaps for long campaigns:

- A character's location and inventory are not first-class records. Character facts are flexible JSON maps; the player character starts with a description fact.
- Campaign panel values are scalar quantity, money, text, status, or date values. They work for cash and simple stock counts, but do not represent distinct owned items, stacks, transfers, or per-character equipment.
- Public/private world changes are flexible JSON maps rather than typed operations over stable places and possessions. Existing panel value validation does not provide equivalent item identity or location constraints.
- The player sees a world summary, character facts/activity, and tracked campaign fields, but there is not yet a specific owned-inventory view.

So the present prompt architecture does provide hidden context and durable summaries, but the application cannot yet enforce every item/ownership/location relationship the model should preserve. Do not describe summarization alone as a complete hallucination defense.

## Product direction

1. Add an at-a-glance player board with present surroundings, known character information, companions' visible activity, and the player's owned inventory/resources.
2. Model possessions and campaign resources with stable identity, ownership, quantity/unit, and visibility. Keep freeform campaign traits extensible through validated fields; do not hardcode vineyard or dungeon rules.
3. Represent known places and character presence so a move is an explicit, validated, traceable state transition. Make discovery/visibility a separate decision from GM-private existence.
4. Give the GM authoritative state plus relevant public/private context on each turn. Treat history summaries as retrieval aids; stable entity records and accepted deltas remain canonical.
5. Add cross-session behavioural scenarios for item conservation, transfers, resource arithmetic, hidden facts, NPC location, reconnects, and player-visible traceability.
6. Manually benchmark these tasks against the three tools above using the separate fictional QA campaign. Record screenshots/task outcomes only from the QA campaign; never use or alter the vineyard campaign for testing.

## References

- Friends & Fables, [product overview](https://fables.gg/) and [about page](https://fables.gg/about).
- Kanka, [overview documentation](https://docs.kanka.io/en/latest/overview.html).
- LegendKeeper, [feature list](https://www.legendkeeper.com/features/) and [RPG campaign manager](https://www.legendkeeper.com/rpgs/).
- Apple, [Human Interface Guidelines: Design Principles](https://developer.apple.com/design/human-interface-guidelines/design-principles) and [UI Design Dos and Don'ts](https://developer.apple.com/design/tips/).
