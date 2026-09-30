# Implementation checkpoint — 2026-09-30

Storyteller now has a working gameplay foundation plus its first inventory vertical slice. This is a development checkpoint, not the final product. The local vineyard campaign remains untouched; the automated suite uses the separate `storyteller_test` database and fictional fixtures.

## Implemented in this iteration

- Campaign setup can seed public, player-owned starting items with a name, whole-number quantity, unit, category, and description. Setup review displays the items before creation.
- Campaign state now persists stable inventory item IDs, quantity, owner, visibility, and flexible JSON properties. The GM receives both player-visible and GM-private inventory in its local prompt context.
- Model proposals can add an item, transfer a whole stack to another known character or the party, or consume a positive amount. The domain rejects unknown owners/items, duplicate identities, unknown fields, invalid JSON properties, and quantities above the owned stack.
- Accepted item changes and their audit events commit with the turn. Public and GM-private inventories are stored and projected separately. Free-form world changes cannot replace the inventory collection, and narration alone cannot mutate the ledger.
- The player board shows known items, quantity, category, owner, description, and item properties. Public timeline events explain additions, transfers, and use without revealing GM-only inventory or internal operation reasons.
- Campaign panels continue to represent fungible balances such as vineyard cash, wine stock, and vine stock; named owned items use the inventory ledger.

## Verification

- `mix test`: **100 tests, 0 failures**, including campaign setup/play-board LiveView coverage and Spanish/French inventory board labels.
- `mix format --check-formatted`: passed after formatting the HEEx templates.
- `mix compile --warnings-as-errors`: passed.
- `mix assets.build`: passed.
- `git diff --check`: run before the iteration is committed.
- Tests cover starting inventory persistence, the setup review and rendered play board, public/private projection, inventory operations, invalid changes, prompt context, hidden-event omission, narration with no accepted ledger operation, inventory continuity into a later session, and localized inventory labels. Tests call only fake providers; no live OAuth or model request was made.
- The locally hosted setup route returned HTTP 200 and its rendered HTML contained the starting-item controls. A Windows browser automation attempt was stopped by the computer-use URL-policy guard, so visual browser QA was not completed in this iteration.

## Remaining work before the polished MVP

1. Add first-class canonical places and character presence, then validate NPC/player movement against campaign places and accepted events.
2. Extend inventory editing to support partial transfers, item updates (for example condition or charges), and a clear way to manage inventory after campaign creation. Current transfer moves the whole stack.
3. Improve the character board's current-scene and surroundings information; test it at narrow widths with keyboard and assistive technology.
4. Finish English, Spanish, and French coverage for the new inventory/setup strings; run extraction/merge checks and locale-flow tests.
5. Run a manual, fictional QA campaign through creating a campaign, a normal turn, a consequential D20, inventory changes, session restart/resume, and recovery. Do not retry or change the existing saved QA session with its provider failure.
6. Perform hands-on task benchmarking of Friends & Fables, Kanka, and LegendKeeper against the documented product principles. Current benchmark notes are based on public documentation, not interactive product testing.
7. Confirm current ChatGPT-plan OAuth eligibility and, only after the owner completes consent, run the opt-in real-provider smoke check. No API key or paid inference fallback is part of the selected route.
8. Review the complete vineyard history and obtain approval of any uncertain facts before any import. Never use vineyard data as a test fixture.

Phoenix is running in WSL at `http://127.0.0.1:4000/`; the durable PostgreSQL development data lives separately from test state.
