# Product benchmark: coherent play, not feature count

**Reviewed:** 2026-10-02
**Method:** Review of public first-party product pages and Apple Human Interface Guidelines. No competitor account or feature was hands-on tested. Storyteller evidence below is limited to the separate fictional QA campaign and named automated tests. No Vineyard campaign data was opened or reproduced. No live model request or OAuth flow was performed for this review.

## Product question

Can the player stay immersed in the current scene while the application, rather than a long transcript alone, protects durable world continuity?

The owner’s market-research hypothesis is that an LLM can remember an NPC’s personality while losing practical canon such as travel time and current location. That is a product hypothesis, not a claim about every AI GM. A proposed acceptance exercise is to establish a forty-minute route between two places, leave an employee at the origin, then visit the destination in a later session. The employee must not appear there until a valid move or contact is established. This is a scenario specification, not a test against Vineyard campaign data.

## What public product sources suggest

| Reference | Relevant public evidence | What it suggests for Storyteller |
| --- | --- | --- |
| **Friends & Fables** — AI-native TTRPG | The vendor describes a campaign engine distinct from its GM persona, with game-state tracking and memory retrieval. Its memory notes describe memories linked to characters and places, long-term search, and a player-visible way to inspect context sent to the GM. These are vendor descriptions, not independently verified quality results. [ACE-1 overview](https://fables.gg/blog/introducing-ace-1-the-engine-powering-the-best-ai-ttrpg-experiences) · [Memories V2](https://fables.gg/patch-notes/memories-v2) | Make relevant context retrieval inspectable during debugging, while keeping ordinary play focused on the fiction. Model prose and app-owned canon should have distinct responsibilities. |
| **LegendKeeper** — system-agnostic campaign manager | Its public feature list describes linked wiki pages, maps, calendars and timelines, full-text search, and granular permissions/secrets. This is a campaign organization reference, not a measured AI GM comparison. [Features](https://www.legendkeeper.com/features/) | Provide flexible campaign records and player-safe disclosures, without turning the live play screen into a general-purpose worldbuilding workspace. |

These products inform the benchmark through their stated approaches, not a feature checklist or comparative score. Neither source proves that Storyteller’s own approach improves campaign quality; that requires repeated play tasks and human review.

## Interaction guidance applied

Apple’s HIG recommends giving essential information room and placing it by importance; hiding secondary detail until relevant; and keeping routine status feedback near the thing it describes. These principles map well to a tabletop board: orient the player first, disclose deeper details in context, and show a state change where it belongs rather than interrupting narration with bookkeeping. Apple guidance is a design reference, not a claim that Storyteller is an Apple-platform product. [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) · [Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls) · [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)

## Implications for the next player-facing iteration

1. **Make the current scene legible at a glance.** Give the location, in-world time and weather, immediate situation, and characters actually present clear priority. Show only inventory and campaign resources relevant to the character or genre; put settings and deep campaign records behind nearby, plainly labeled disclosures.
2. **Keep fiction and bookkeeping in their proper places.** Narration and character speech belong in the conversation. Accepted date, weather, location, presence, inventory, and resource changes should update their own board panels with restrained feedback tied to the changed item. Keep the player’s submitted action visible while the GM responds.
3. **Treat relevance and secrecy as one context boundary.** Keep full canon durable server-side, retrieve a compact subset based on current place, present characters, and the player’s action, and keep GM-only facts out of every player-facing projection. Test for both required facts being included and plausible but irrelevant/off-scene details being excluded; do not use a prompt byte ceiling as proof of token cost or continuity quality.

## Storyteller evidence and limits

- **Recorded QA play:** In one previously observed turn in the separate fictional Quiet Observatory QA campaign, the player asked about job terms at a tavern bar. The GM introduced an employer in narration and dialogue; the scene roster then showed her at that location with the existing companion. The saved player action remained visible while the GM responded. This is one turn, not proof of multi-session continuity, overall prose quality, or comparative performance.
- **Behavior tests:** A fake-provider sparse-scene observation test checks that a brief ambient impression leaves world state, inventory, character presence, elapsed time, revision, and prior events unchanged; the serialized request stays under its 10,000-byte test ceiling. A production-boundary regression covers direct and indirect scene questions over a 2,400-event/100-session fixture in English, Spanish, and French: current-place detail is retained while connected-place decoys are excluded, within a 24,000-byte preflight ceiling. Other synthetic fixtures cover 240-event retrieval and selected cross-session schedule, promise, decision, work-plan, and next-step cues with decoys. These are bounded cue/retrieval tests, not general semantic search or proof of live-GM quality.
- **Cost and human review:** Byte limits are conservative serialized-request proxies, not token counts. The benchmark has no provider-reported usage comparison and makes no cost-savings claim. A human still needs to review live writing quality and repeat representative tasks across resource, exploration, and social campaigns.
- **Scope boundary:** No competitor was tried hands-on, and no private campaign text is included here. The visual browser experience and multi-session scenario above are not a controlled comparative study.

## Next benchmark tasks

Use the same player tasks in future QA: identify the current place and who is present; inspect owned items/resources; retrieve an old commitment; distinguish what the player knows from GM-only context; and recover after a failed turn. Record task success, time-to-understanding, continuity errors, and request size separately. Do not collapse these into a feature count or market claim.

## 2026-10-02 source refresh

Additional first-party pages were reviewed for this update. Some Friends & Fables details below come from dated product posts and may not describe the current default; they remain desk research, not hands-on verification:

- Friends & Fables’ current homepage markets an AI GM, world-building tools, and an integrated text-RPG/VTT product. Its dated July 2024 launch post described at-a-glance location/nearby-NPC information and a travel system tracking character locations. The Dec. 2024 ACE-1 article documents a distinct campaign engine, visible context inspection, and Adventure/Downtime pacing; its June 2025 Memories V2 post describes fewer, larger short-term memories and retrieval of older memories linked to characters and places. These are vendor descriptions, not evidence of continuity accuracy in a matched play test. [Current product overview](https://fables.gg/) · [2024 standalone platform post](https://fables.gg/blog/a-new-chapter) · [2024 ACE-1 post](https://fables.gg/blog/introducing-ace-1-the-engine-powering-the-best-ai-ttrpg-experiences) · [2025 Memories V2 post](https://fables.gg/patch-notes/memories-v2)
- Kanka advertises optional campaign categories, role-tailored dashboards, inventories on entries, and custom calendars. Its documentation also warns that too many dashboard widgets can make a campaign harder to use. This supports flexible campaign state while cautioning against putting every tracked field on the play board. [Features](https://kanka.io/features) · [Dashboard guide](https://docs.kanka.io/en/latest/guides/dashboard.html) · [Inventory guide](https://docs.kanka.io/en/latest/features/inventory.html)
- Apple's refreshed design principles emphasize purpose, agency, familiarity, feedback, simplicity, craft, and delight; its simplicity guidance explicitly values “exactly enough,” while natural animations can help preserve context. This supports the current scene-led board and restrained panel feedback rather than visual decoration or a dashboard packed with fields. [Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles)

Product decision: keep pacing player-led through the existing Act, Ask, and Pass time controls until QA shows that a separate pacing setting solves a real problem. Keep the immediate board limited to the current scene, present characters, and the campaign's relevant inventory/resources. Prioritize a matched Finca/Bodega continuity task and an old-commitment recall task over additional maps, dashboards, or provider-side memory features. This is an inference from the published patterns and Storyteller's goal; no competitor was used hands-on, and no product was ranked.
