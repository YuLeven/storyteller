# Implementation checkpoint — 2026-09-30

Storyteller has a working Phoenix LiveView gameplay loop with durable sessions, a player-controlled D20, bounded GM memory, configurable campaign panels, and initial inventory and location ledgers. This remains an active product iteration, not a final release. Vineyard campaign data has not been imported or used for tests; ExUnit runs against the separate `storyteller_test` database.

## Implemented

- Reviewed campaign setup seeds stable player-owned inventory entries, public world details, GM characters, and typed campaign panels. Inventory supports stable IDs, flexible properties, quantity, unit, category, owner, and visibility.
- The GM receives canonical public and private inventories. Validated add, whole-stack transfer, and consume operations commit atomically with timeline events; generic state changes cannot edit or replace inventory.
- Campaigns persist campaign-scoped places with stable IDs, descriptions, JSON surroundings, and public or GM-private visibility. The starting world location seeds the player's first place, and a GM character's explicitly visible location seeds known presence.
- The GM receives both visibility scopes for places and every character's current place. Place creation must precede movement; movement uses a known character and place, and the player cannot move to a GM-private place. Location changes commit with the turn. Generic world changes cannot overwrite the canonical location.
- The play board shows the player's current place and surroundings, who is publicly present, tracked campaign resources, owned items, character details, and the campaign story. Public history and projections omit GM-private places and presence.
- Campaign history and world state continue across sessions; a new session resumes the same inventory, places, and character positions.
- Spanish and French catalogs include the inventory and location-board labels. Campaign-authored content remains in its selected narration language.
- Added an idempotent fictional QA seed, **The Amber Orchard**, with a starting place, NPC presence, flexible orchard stock panels, and a player-owned basket. It is separate from both the existing failed observatory QA turn and the vineyard campaign.

## Verification

- `mix test`: **110 tests, 0 failures**; focused location and play LiveView tests cover seeded presence, movement, private-place isolation, invalid free-form teleportation, and persistence into a later session.
- Locale LiveView tests pass for Spanish and French current-place labels, public presence, and inventory content.
- `mix format`, `mix compile --warnings-as-errors`, and `mix assets.build` passed during this iteration; rerun the format check and `git diff --check` before committing.
- `mix gettext.extract` and `mix gettext.merge priv/gettext` completed. Ten new location strings were translated in both Spanish and French.
- The seeded QA campaign's local session page returned HTTP 200 and rendered the starting place, inventory, and public stock; its GM-private note was absent from the player HTML. This was an HTTP/LiveView check, not visual browser QA.
- Automated tests use fake providers only. No OAuth consent or live model request was made.
- HTTP/browser review has not been completed for the new board. The previous Windows browser automation attempt was rejected by the computer-use URL-policy guard. Continue with local HTTP and LiveView behavior checks; do not change the existing failed QA turn.

## Next work

1. Extend inventory operations with partial transfers, item edits (such as condition or charges), and a clear way to manage inventory after campaign creation.
2. Continue exercising the fictional **The Amber Orchard** QA campaign through normal play, a consequential D20, inventory and location changes, session restart/resume, and recovery. The UI is seeded, but a live GM turn still needs the owner to complete OAuth consent; fake-provider behavior remains covered by ExUnit. Never reuse the vineyard campaign or its data for tests.
3. Compare hands-on campaign and AI role-playing tasks in Friends & Fables, Kanka, and LegendKeeper against the product goals and Apple's interaction design principles. Current notes are based on public documentation, not interactive product testing.
4. Check keyboard use, screen-reader labels, small-screen layouts, and readable contrast on the play board.
5. Recheck the ChatGPT-plan OAuth preview eligibility and run a live-provider smoke check only after the owner completes account consent. Do not add API billing or an API-key fallback.
6. Review the complete vineyard history and request confirmation only for uncertain campaign facts before any import.

The WSL PostgreSQL development database is separate from test data. Check the current Phoenix server status before relying on `http://127.0.0.1:4000/`.
