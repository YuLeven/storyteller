# Feature log

## 2026-10-02 — Exercise continuity at the production turn boundary

- Added an isolated fake-provider `Play.submit_turn` regression over 100 synthetic sessions and 2,400 persisted events. The request retains an old Finca/Bodega travel-and-duty fact, all 12 newest events, and canonical character locations, active duty, and route data, while unrelated old history is omitted.
- Compared serialized request bytes with a full-history baseline: the compact request stays within the configured preflight budget and is less than one-fifth the baseline size. This is a byte-size proxy, not provider token usage; the fake provider makes no live AI request.
- **Checks:** focused production-boundary Play regression passed (1 selected, 0 failures); full WSL suite passed (**375 tests, 0 failures**); warnings-as-errors compilation, formatter, Gettext freshness, and `git diff --check` passed. All campaign fixtures use the isolated `storyteller_test` database; no live campaign, Vineyard data, live provider, or OAuth was used.

## 2026-10-02 - Trace campaign voice edits through the provider request

- The rendered campaign-editor regression changes accent, cadence, and mannerisms, submits the current form without replaying the earlier `phx-change` payload, checks the persisted character record, and reopens the editor. It then starts a turn on the same fictional campaign with a fake provider that captures the production-built request. The exact edited accent, cadence, and mannerism values remain attached to the same present NPC in that request.
- This verifies persistence-to-prompt delivery, not whether a model performs the voice convincingly. No save or prompt-delivery defect reproduced in the isolated regression.
- **Checks:** campaign-authoring LiveView (8 tests, 0 failures), authoring domain (13 tests, 0 failures), formatter check, and `git diff --check` passed under WSL with `MIX_ENV=test`. The provider was an injected fake; no development database, live campaign, Vineyard data, live provider, or OAuth used.

## 2026-10-01 - Recall seasonal reserves from common set-aside paraphrases

- Added a small set of reviewed English (`save`/`saved`), Spanish (`apartamos`/`separamos` and participles), and French (`garder`/`gardé`/`gardée`/`gardons`) aliases for the existing allocation concept. Seasonal retrieval still requires both the allocation concept and tasting/event support, so same-tasting schedule and menu details stay compact when the player asks specifically about the reserve.
- Extended the fake-provider later-session regression with natural English, Spanish, and French questions. It verifies the reserve detail and provenance arrive, schedule/menu decoys retain identity/status only, and each request remains within the 24,000-byte preflight bound.
- **Checks:** full WSL suite passed (**374 tests, 0 failures**); focused Play regression (1 test, 0 failures), ContextBudget suite (18 tests, 0 failures), and formatter check also passed against `storyteller_test`. No development database, campaign data, Vineyard, live provider, or OAuth used.

## 2026-10-01 - Protect campaign voice edits across open tabs

- Campaign edit forms now submit the current setup-correction sequence. A stale tab cannot silently restore older voice or mannerism fields over newer saved values; it shows a conflict, keeps its own draft visible, refreshes to the latest revision, and can save again after review.
- Added a two-tab LiveView behavior test that verifies the newer mannerism survives the stale save, the pending accent remains visible, and an intentional retry combines both values. Updated the campaign-edit acceptance scenario and removed stale wording that still described correction notes as required.
- **Checked:** new two-tab scenario and campaign-authoring unit/LiveView suites passed (**21 tests, 0 failures**); full isolated WSL suite passed (**374 tests, 0 failures**); warnings-as-errors compilation, formatting, Gettext freshness, and `git diff --check` passed. Tests used `storyteller_test` and fake providers only.

## 2026-10-01 - Save voice guidance without a required explanation

- Campaign voice and mannerism edits no longer get blocked by a required correction-reason field. The note is optional; when blank, the correction history receives a general campaign setup reason. A written explanation is retained when provided.
- Updated the edit-page copy in English, Spanish, and French. Strengthened the voice-only LiveView regression to save without a note, verify the correction record and stored voice fields, and reload the editor.
- **Checked:** campaign-authoring LiveView suite (7 tests, 0 failures); warnings-as-errors compilation, formatter, Gettext freshness, and `git diff --check` passed. The test used the isolated test database.

## 2026-10-01 - Verify character voices in the final GM request

- Added a fake-provider gameplay regression with two present NPCs and distinct voice notes. It inspects the exact context sent through the production request builder and verifies each speaker ID retains only its own profile and canonical shared location.
- **Checked:** focused Play test passed. This proves prompt delivery and speaker association, not the model's ability to perform the voices distinctly; multi-turn live voice evaluation still needs an owner-approved provider request.

## 2026-10-01 - Explain safely rejected GM replies

- The turn-recovery card now uses the persisted safe failure stage for malformed or rejected GM responses to explain that none of the reply was added to story or canonical state. It keeps the submitted action visible and the existing same-turn retry path available without exposing raw output or private context.
- Translated the new recovery message into Spanish and French. Updated the recovery acceptance brief and changed the retry regression to drive a malformed provider response, verify `response_decoding`, preserve the saved action, hide raw response text, and complete that same turn on retry.
- **Checked:** SessionLive suite (55 tests, 0 failures), warnings-as-errors compilation, formatter, Gettext freshness, and `git diff --check` passed. Only the isolated `storyteller_test` database and fake provider were used.

## 2026-10-01  Show when streamed GM narration begins

- A turn now gets a quiet progress update after the provider sends its first non-empty text delta. The player action stays visible; generated text is withheld until the entire response is complete, validated against campaign canon, and committed. Failed or incomplete streams never appear as story.
- Opening scenes receive the same honest progress cue and still keep the player composer disabled until the opening scene commits. Resolution now starts from the connected LiveView, so its progress signal reaches the active play screen instead of a disconnected render process.
- Added numeric-only time-to-first-text-delta telemetry and fake-SSE plus LiveView regressions for exactly-once notification on the first non-empty chunk, no callback when a stream has no text, no callback leakage into the HTTP body, saved-action visibility, and canonical-only narration; an error after partial text still cannot surface generated content.
- Checks: adapter and SessionLive suites (74 tests, 0 failures); full isolated suite (372 tests, 0 failures); warnings-as-errors compilation, formatter, Gettext freshness, and git diff --check passed. All Elixir work ran in WSL against storyteller_test; no live provider, OAuth, development campaign, or Vineyard data was used.
- Limit: the progress cue means streamed text has started, not that a valid GM response is ready. The latency measurement includes OAuth access and request setup, is transient Telemetry only, and does not persist per-turn timings.

## 2026-10-01 — Recall a Spanish set-aside fact without tasting decoys

- Added the single bounded alias `guardamos` → `allocation:set-aside`. With the existing `cata` and `otoño` cues, the question “¿Qué guardamos para la cata de otoño?” now requires both a tasting and set-aside match. Other notes about the same tasting, such as its schedule or menu, remain compact.
- Added a fake-provider regression that establishes the reserve fact and two same-topic decoys in a fictional Quiet Observatory session, starts a later session, and checks the captured request context. The earlier behavior already included the reserve but also expanded the schedule decoy; the new cue keeps both decoys to stable identity/status metadata. The test checks provenance points to the earlier session and enforces the 24,000-byte preflight bound.
- **Checks:** focused context-budget, Play, and story-memory suites passed (**107 tests, 0 failures**); WSL formatting check and `git diff --check` passed. Tests use the isolated `storyteller_test` database and fake providers; no live provider, OAuth flow, Vineyard campaign, or development database was used.
- **Limit:** this covers the exact Spanish form `guardamos` with `cata` and `otoño`. Other inflections, paraphrases, and general semantic retrieval remain untested and unsupported.

## 2026-10-01 — Preserve voice edits when game time advances

- A campaign edit page shows the remaining duration for active GM-character duties. If game time advanced while the page stayed open, submitting those unchanged durations could make them look like new duty edits and reject otherwise valid voice or mannerism changes as stale.
- The editor now omits duty values that still match the page's original snapshot. Explicit duty edits remain revision-checked; unchanged duties retain their original absolute release time while voice guidance saves.
- Added an isolated LiveView regression that advances the fictional world clock between opening the editor and saving voice guidance, then verifies both the voice notes and the duty deadline.
- **Checks:** campaign-authoring LiveView suite (**7 tests, 0 failures**); campaign-authoring service suite (**13 tests, 0 failures**); SessionLive suite (**53 tests, 0 failures**). Test-environment warnings-as-errors compilation, formatting, Gettext freshness, and `git diff --check` passed. Tests ran in WSL against `storyteller_test`; no live provider or Vineyard campaign was used.

## 2026-10-01 — Keep unsent player actions through submission races

- If a fresh GM turn or account-wide ChatGPT pause arrives just as the player submits, the LiveView now keeps that unsaved text in the composer and explains why it was not accepted. The draft stays local until the player explicitly sends it; turn completion or resuming requests never submits it automatically. The database-conflict `:turn_already_open` path also retains the attempted text.
- Added LiveView behavior regressions for a follow-up racing an active turn and an action racing a usage pause. They confirm the first turn remains unique, the follow-up stays visible and unsent, plan resume makes no provider call, and the player can explicitly submit the preserved draft afterward.
- **Checks:** focused regressions (**2 tests, 0 failures**); full SessionLive behavior suite (**53 tests, 0 failures**); `MIX_ENV=test mix compile --warnings-as-errors`, `mix format --check-formatted`, Gettext freshness, and `git diff --check` passed. Tests ran in WSL with the isolated test database and a fake GM provider; no live provider, OAuth consent, or Vineyard campaign was used.

## 2026-10-01 — Correct public inventory item details in place

- Added a reasoned, revision-checked inventory `edit` correction for item name, quantity, unit, category, description, owner, and the complete flexible-properties JSON object. The item is normalized through the inventory domain validator; its stable ID and visibility are retained, and full before/after snapshots stay in the correction ledger. Existing add, quantity/owner set, and remove actions keep their behavior.
- Exposed the edit action from the campaign correction panel and prefilled the selected item's current values. Public correction options continue to omit GM-private inventory, and attempts to edit a private item are rejected. Zero quantity remains available through the existing set/remove path rather than silently deleting during an edit.
- Added service and LiveView behavior coverage for all editable fields, nested properties, stable identity, audit snapshots, the updated public projection, private-item exclusion, and out-of-story correction behavior.
- **Checks:** focused Play and SessionLive suites (**133 tests, 0 failures**); full WSL suite (**364 tests, 0 failures**); `MIX_ENV=test mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix gettext.extract --check-up-to-date`, and `git diff --check` passed. Tests use the isolated `storyteller_test` database and fake providers; no live provider, Vineyard campaign, or OAuth flow was used.

## 2026-10-01 — Keep the campaign save requirement in view

- Moved the required correction-reason field and save feedback to the beginning of the campaign edit form. The requirement is now visible before character voice and mannerism fields, rather than appearing after the long form where a blocked save could look like edits were ignored.
- Extended the LiveView regression to assert that ordering, confirm a missing reason does not alter saved voice data while retaining the draft, then save with a reason and verify values after reopening.
- **Checks:** campaign-authoring LiveView suite (**6 tests, 0 failures**); full WSL suite (**362 tests, 0 failures**); `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix gettext.extract --check-up-to-date`, and `git diff --check` passed. Tests use the isolated `storyteller_test` database; no live campaign or provider request was used.

## 2026-10-01 — Measure GM provider call latency safely

- Each provider invocation emits monotonic wall-clock duration plus numeric success/failure counts; the claimed-turn resolution emits a second duration spanning local context construction, validation, and persistence. Comparing them helps identify whether a slow turn is mostly provider wait or application work. Telemetry metadata is empty; campaign IDs, model names, prompts, response text, and provider errors are not attached. `Telemetry.Metrics` defines summaries for a configured reporter.
- Added fake-provider end-to-end behavior coverage for successful and failed turns, asserting both numeric-only measurements, empty metadata, and provider duration no longer than total resolution duration. Neither measurement includes LiveView rendering or browser/network delay.
- **Checks:** focused provider/resolution timing behavior (**2 tests, 0 failures**); full WSL suite (**362 tests, 0 failures**); `mix format --check-formatted`, test-environment warnings-as-errors compilation, Gettext freshness, and `git diff --check` passed. Tests use isolated fixtures and `storyteller_test`; no live provider or OAuth call.

## 2026-10-01 — Make campaign correction reasons an explicit save requirement

- Voice and mannerism edits are stored as audited setup corrections, which require a reason. The edit form now marks that field as browser-required so a voice edit cannot appear to submit without the reason needed to commit it.
- Added a LiveView behavior regression for a blank-reason save: the validation message appears while voice drafts remain visible; supplying a reason then saves the guidance and reopening the editor confirms it persisted.
- **Checks:** campaign-authoring LiveView suite passed (**6 tests, 0 failures**); full WSL suite passed (**360 tests, 0 failures**); formatting, test-environment warnings-as-errors compilation, Gettext freshness, and `git diff --check` passed. Tests use isolated fixtures; no live campaign or provider request was used.

## 2026-10-01 — Require established public paths for remote NPC messages

- Added an explicit public communication-path ledger to serialized campaign state. A known NPC may establish a path only while publicly present with the player, with a path operation citing the exact public dialogue line as its basis and naming the usable endpoint plainly in that line. `public_changes` and its case/separator-normalized aliases cannot seed the ledger. Establishment/deactivation write public before/after `state_change` audit records atomically, outside the story timeline. Remote deliveries require the previously persisted active path ID and matching sender; the message turn cannot move characters, edit travel routes, or advance world time. Ordinary off-scene dialogue and activity checks remain unchanged.
- Remote deliveries are stored as `remote_message` events and shown with a distinct timeline style and sender label. At most 12 active paths enter GM context, ranked by query match and recency; the test keeps an older matching path available among 40 unrelated paths while staying within the serialized-byte bound. Backup schema v11 round-trips paths/messages; imports v1–v10 remain compatible and default to an empty path ledger.
- Added fake-provider behavioral coverage for valid establishment and delivery, absent/inactive/mismatched paths, no path inference from narration or hidden endpoints, unchanged remote NPC location/time on delivery, distinct timeline typing/rendering, and backup round-trip/legacy compatibility.
- **Checks:** the focused fake-provider Play suite passed (**6 tests, 0 failures**), including direct/alias ledger-seed rejection, audit before/after for establishment and deactivation, path selection among 40 unrelated entries, and the 24 KB context bound. The selected remote-message LiveView and legacy-backup tests passed (**62 tests, 0 failures, 60 excluded**). Test-environment warnings-as-errors compilation, `mix format --check-formatted`, `mix gettext.extract --check-up-to-date`, and `git diff --check` passed. Tests used the isolated `storyteller_test` database; no live provider, live campaign, Vineyard data, or OAuth flow was used.
- **Latest regression pass:** the full WSL suite passed (**360 tests, 0 failures**) after adding strict v10 rejection for v11 communication-path state and remote-message events; no provider calls or live campaign data were used.

## 2026-10-01 — Preserve validated voice edits on save

- The campaign editor accumulates character setup, duty, and voice drafts across validation events, then combines them with the final save payload. Voice and mannerism edits survive partial validation/submit payloads, and explicit submitted values, including cleared values, take precedence. The correction reason is retained across those partial events too.
- Added a LiveView regression for a colon-bearing NPC ID that edits accent and mannerisms, submits without the nested voice map, and verifies the values persist after reopening the editor.
- **Checks:** campaign-authoring LiveView suite passed (**6 tests, 0 failures**); full WSL suite passed (**352 tests, 0 failures**); `mix format --check-formatted`, Gettext freshness, test-environment warnings-as-errors compilation, and `git diff --check` passed. All tests used isolated fixtures; no live campaign or provider request was used.

## 2026-10-01 — Retrieve social commitments from indirect multilingual cues

- Added a small deterministic alias vocabulary for future meetings and replies across English, Spanish, and French. The new relation retrieves details only for typed commitments; same-topic facts stay compact, and unrelated commitments remain omitted.
- Added compiler regressions for appointment/meeting and reply/answer cues in all three languages, plus a fake-provider cross-session scenario that preserves meeting and reply commitments while excluding same-topic fact decoys and an unrelated commitment. Every request asserts the existing 24,000-byte preflight bound.
- **Checks:** the complete context-budget suite and new cross-session Play regression passed (**97 tests, 0 failures**); full WSL suite passed (**351 tests, 0 failures**); formatting, Gettext POT freshness, test-environment warnings-as-errors compilation, and `git diff --check` passed. Tests use the isolated test database and fake providers; no live campaign or provider request was used.

## 2026-10-01 — Make multi-day time passage easy to request

- Added a **Pass a few days** nudge in Let time pass mode. Its text asks the GM to stop at the next meaningful decision the player needs to make; the free-form duration path remains available. Spanish and French copy is included.
- Added a fake-provider LiveView regression that submits the nudge as time_passage, advances the canonical clock by exactly three days, returns control with a new decision point, and confirms no player action, roll, or character movement is invented.
- Updated the UX acceptance criteria for the contextual multi-day nudge and retained the existing time-passage agency contract.
- **Checks:** campaign-authoring and session LiveView suites passed (**54 tests, 0 failures**); full WSL suite passed (**349 tests, 0 failures**); formatting, Gettext POT freshness, test-environment warnings-as-errors compilation, and `git diff --check` passed. Tests used isolated fixtures and fake providers.

## 2026-10-01 — Keep edited character voices visible through save and reload

- The campaign editor now keeps a character's voice and mannerism section expanded while it has draft edits or saved guidance. After a successful save, the newly persisted values remain visible instead of disappearing into a closed disclosure.
- Strengthened the LiveView regression to start with no voice guidance, validate cadence and mannerism edits, verify the save confirmation and expanded state, then reopen the editor and confirm both saved notes remain visible.
- **Checks:** campaign-authoring and session LiveView suites passed (**54 tests, 0 failures**); full WSL suite passed (**349 tests, 0 failures**); formatting, Gettext POT freshness, test-environment warnings-as-errors compilation, and `git diff --check` passed. Isolated fixtures only; no live campaign data or provider request.

## 2026-10-01 — Preserve character voice edits in the campaign editor

- Campaign editor validation rerendered GM character cards from the last persisted values, so voice and mannerism text could disappear before the owner saved it. The editor now retains submitted character setup, duty, and voice drafts through validation and save errors, clears them after a successful save, and reloads the committed values on a fresh visit.
- Added a LiveView regression that changes voice fields, triggers validation, saves, and reopens the editor. Existing campaign-authoring behavior verifies saved guidance reaches future GM context without rewriting earlier dialogue.
- **Checks:** campaign editor LiveView **5 tests, 0 failures**; campaign authoring **13 tests, 0 failures**; full WSL suite **346 tests, 0 failures**. Formatting, Gettext freshness, warnings-as-errors compilation, and `git diff --check` passed. No live campaign data or provider request was used.

## 2026-10-01 — Let the operator choose the GM model

- Added a local installation-wide GM model preference. New installations keep the existing automatic account-catalog selection; a saved choice is passed into turn compilation and the Responses request, so the same listed model is requested on subsequent turns.
- The collapsed Account and GM model settings show the current preference and the connected account's available models. The selector is outside the play board, accepts only models in the current catalog, and offers a return to Automatic. Existing OAuth connection and disconnect behavior remains unchanged.
- Added fake-catalog account-page coverage, local preference persistence coverage, and a fake-provider play regression asserting the saved model reaches turn resolution. No live account/API request or production campaign data was accessed.
- **Checks:** Settings/account controller tests **7/7**; saved-model Play regression **1 selected, 0 failures**; OpenAI adapter tests **16/16**; full WSL suite **346 tests, 0 failures**. Formatting, Gettext POT freshness, warnings-as-errors compilation, and `git diff --check` passed. Tests used `storyteller_test` and a fake model catalog/provider.

## 2026-10-01 — Skip the catalog round trip for a saved GM model

- Turns with an explicitly saved model now send that model directly to Responses, removing the per-turn `/v1/models` request. Automatic selection still fetches the account catalog and chooses its first listed model.
- The account settings summary now shows that effective first-listed model (display name and slug) in Automatic mode, the selected model when pinned, or a translated stale-choice notice if the saved slug is no longer in the catalog. The summary is localized in English, Spanish, and French.
- The settings save path validates choices against the connected account catalog. A choice can become stale after it is saved; a provider `model_not_found`/unavailable response remains a recoverable `model_unavailable` turn failure, and the operator can choose another model or return to Automatic.
- Fake-HTTP coverage verifies the selected-model request skips catalog lookup, automatic still selects from the catalog, and a stale saved model's provider error maps to `model_unavailable`. No live account/provider request or campaign data was used.
- **Checks:** OpenAI adapter **17 tests, 0 failures**; full WSL suite **348 tests, 0 failures**; formatting, Gettext freshness, warnings-as-errors compilation, and `git diff --check` passed. Tests used the isolated test setup and fake HTTP/catalog.

## 2026-10-01 — Bound GM context across every continuity-memory source

- The context compiler now selects relevant details from both GM-authored and player-managed continuity entries in public and GM-private scopes, with an eight-detail cap per scope. Other entries retain stable identity, type, and status metadata, while a completeness marker tells the GM that omitted detail is unknown. Full records remain persisted and visible only through their correct campaign views; a relevant canon item that still exceeds the hard input bound continues to fail recoverably.
- A fake-provider play regression has the GM establish a typed commitment and an unrelated decoy in one session, then asks a broad “what did we agree?” question in the next. The request retains the commitment details and omits the decoy details. Hidden-memory coverage confirms relevant private detail remains within GM context and out of player-visible projections.
- **Checks:** ContextBudget **17 tests, 0 failures**; new cross-session Play behavior **1 selected, 0 failures**; story-memory correction suite **6 tests, 0 failures**; full WSL suite **342 tests, 0 failures**. Formatting, warnings-as-errors test compilation, and `git diff --check` also pass. No live provider call or campaign access was used.

## 2026-10-01 — Retrieve typed commitments from broad promise questions

- General “what did we agree?” questions now retrieve details from public campaign memories explicitly typed as commitments, even when the question omits the commitment's subject. English, Spanish, and French prompts are covered. Retrieval remains bounded to the eight-detail cap; omitted details are marked incomplete, and a non-commitment fact containing the word “promised” stays out of detailed context.
- The product benchmark now spells out the end-to-end Finca/Bodega exercise: later-session character presence must follow canonical travel/contact state without requiring the player to restate or manually save the route, while unrelated history is excluded and context cost stays measurable.
- **Checks:** ContextBudget **17 tests, 0 failures**; full WSL suite **341 tests, 0 failures**; formatting, warnings-as-errors compilation, and `git diff --check` pass. Automated coverage uses the isolated test database and synthetic campaign data; no live provider request or Vineyard data was used.

## 2026-10-01 — Retrieve indirect employment details without broadening toll matches

- Job-memory retrieval now covers bounded English, Spanish, and French schedule/terms questions and promise/agreement references. The matcher requires a work or acceptance cue alongside schedule terms, and both commitment and work cues for a promise, so generic bridge hours or toll-payment questions do not pull in the employment note.
- Tests include positive indirect phrasings in all three languages and same-topic bridge-hour/toll decoys. This is still a curated lexical relation system, not general semantic search; open-ended paraphrases without a mapped cue can still miss.
- **Checks:** ContextBudget **16 tests, 0 failures**; full WSL suite **340 tests, 0 failures**; retry/account-pause LiveView selection **3 tests, 0 failures**; formatting, Gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. The JavaScript suite passes **13/13**.

## 2026-10-01 — Stress-test continuity across 100 synthetic sessions

- Added a 2,400-event synthetic history spanning 100 sessions. The compiler preserves the old Finca/Bodega route-and-duty fact, the latest 12 turns, and canonical character locations, duties, route, and inventory, while dropping unrelated older events.
- The bounded request stays within the configured input ceiling, within 2 KB of a 12-event baseline, and at least 5× smaller than the full-history request. This verifies scale and context economy for the labeled fixture; it does not establish general semantic recall or replace multi-session play testing.
- **Checks:** focused long-campaign regression **1 test, 0 failures**; full WSL suite **340 tests, 0 failures**. No campaign database or provider request was used.

## 2026-10-01 — Confirm retry gating during an active account usage pause

- Read-only inspection of separate QA campaign 35/session 36 found its current saved action visible while the account-wide ChatGPT usage pause is active. The retry control is present but disabled, and the pause notice offers the explicit resume path. No retry, resume, or provider request was made during this inspection.
- The state matches the designed pause gate. Fake-provider LiveView coverage verifies resume makes no provider call and makes the same saved turn retryable; the live account remains unverified until its usage pause ends.

## 2026-10-01 — Preserve safe scene atmosphere without inventing canon

- A read-only QA review found the canon-first look-around rule could leave a sparse room feeling like a missing record. The GM may now add one short, source-free ambient cue consistent with the known place, time, and weather. People, items, routes, exits, hazards, clues, services, and other actionable facts still require accepted canon; people also require accepted presence. If a player action depends on something untracked, the GM should ask or state uncertainty.
- The GM now prefers one concise utterance per character per turn, combining related statements into one bubble. This reduces chat noise while preserving direct character dialogue and the paced timeline.
- The Ask GM regression uses a vivid ambient answer and verifies the public/private world state, inventory, character locations, elapsed clock, revision, and prior events remain unchanged; only the player question and GM narration are appended. The ordinary prompt remains under its **10,000-byte** behavior ceiling.
- **Checks:** focused Play tests **2 selected, 0 failures**; ContextBudget **16 tests, 0 failures**; full WSL suite **339 tests, 0 failures**. Formatting, Gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. The separate QA account remained usage-paused; no live provider request or campaign edit was made.

## 2026-10-01 — Retrieve employment commitments across English, Spanish, and French

- A durable English memory that records a promise to clarify an employer's offer now survives later Spanish or French paraphrases, as well as direct pay questions in all three languages. Retrieval uses an explicit, reviewed employment/acceptance/compensation vocabulary; it does not claim general semantic search.
- Long, unrelated bridge and harvest notes retain only summary metadata and are omitted from each compiled request. The relevant note is preserved, and both serialized context reduction and the configured conservative input bound are checked.
- **Checks:** ContextBudget **16 tests, 0 failures**; full WSL suite **339 tests, 0 failures**. Tests use synthetic context and fake providers; no live provider or campaign data was used.

## 2026-10-01 — Let persisted world time complete GM-character duties

- Finite owner-authored duties now store an absolute `release_at_world_minute`, anchored to the campaign's persisted elapsed minute at assignment or edit. An indefinite assignment still blocks departure until owner release. The edit form accepts remaining in-world minutes, including 0 to complete an existing duty at the current stored minute; clearing the duty name releases it even if a stale duration value remains in the form. New setup accepts finite durations from 1 to 525600 minutes.
- A route-valid move checks duty availability against pre-turn elapsed time, then checks again against the locked state before commit. The attempted move cannot advance its own clock past the duty threshold. Any earlier accepted turn may pass the threshold; later movement becomes available and still records the canonical route duration. Ask GM and rejected/failed turns do not advance world time. Duty status and threshold remain GM-private; context marks an expired duty completed/available without deleting its audit history.
- Migration `20261001000700` adds the nullable deadline and keeps indefinite existing records compatible. Backup schema v10 round-trips thresholds, rejects an active duty whose character is away from its duty place based on the backup's elapsed clock, and still imports v1–v9 with legacy duties treated as indefinite.
- Updated the campaign setup/edit controls, Spanish and French translations, authoring audit snapshots, plan, UX acceptance contract, and this log. Tests cover assignment/edit anchoring, immediate completion, clear-name correction, no same-turn bypass, a separate accepted time advance, subsequent Finca–Bodega movement, backup v10 round-trip, malformed active-v10 location, and v9 import.
- **Checks:** backup suite **12 tests, 0 failures**; campaign-authoring and LiveView suites **36 tests, 0 failures**; focused finite-duty Play and prompt-size regressions passed. The broad connected-place/scene-speaker retrieval regression now passes with the bounded anchor fallback, and ContextBudget passes **15 tests**. Full WSL suite: **338 tests, 0 failures**; formatting, Gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. Automated tests used the isolated test database and fake providers; no development campaign rows, Vineyard data, or live provider were used.

## 2026-10-01 — Retrieve broad seasonal questions as bounded candidate sets

- “Tell me about the fall event?” can refer to more than one established event. Retrieval now keeps event and tasting concepts distinct, while treating tastings as a kind of event. A broad seasonal event question can therefore give the GM both the autumn tasting commitment and the autumn fundraiser; a question about the quantity earmarked keeps only the tasting commitment. Same-season roof repairs and an unrelated bridge agreement remain out of those answers. English, Spanish, and French behavior is covered through the fake-provider path.
- Broad matches are limited to the eight newest relevant player-managed memories. When older details are omitted, the existing completeness notice tells the GM not to treat the supplied candidate list as exhaustive; GM instructions now say to surface supported alternatives or ask which one the player means. This bounds the number of note details added, while the existing request-size gate still enforces the configured input ceiling.
- **Limit:** retrieval uses a small curated vocabulary and one event-to-tasting relation; it does not understand arbitrary paraphrases or infer event categories. Omitted candidates remain available on the campaign board and may require more specific wording to retrieve.
- **Checks:** focused WSL run with a reduced Erlang scheduler count and `--max-cases 4`: context-budget and story-memory suites, **20 tests, 0 failures**. The new behavior checks that the serialized UTF-8 byte/framing bound stays under the configured 24,000 input ceiling for multilingual questions and a 10-note candidate set; this is a conservative proxy, not an exact token count. Tests use isolated fixtures and fake providers; no existing campaign data or real provider was used.

## 2026-10-01 — Keep account-limit recovery calm on the play surface

- A separate fictional QA session showed the shared ChatGPT usage-limit reason repeated in the global pause notice and the failed opening-scene card. When the account-wide pause is visible, its notice now owns the explanation and resume action; the turn card stays focused on the saved action or the fact that the opening scene still needs to run.
- The opening scene remains blocked until the player explicitly resumes requests, then the same saved scene is retryable. Resume only clears the pause and makes no provider call; an explicit retry resolves that same opening turn once. This does not create a player action or change game state on failure.
- Updated the UX acceptance contract and kept the GM's concise instruction to offer alternatives for multiple matching memories within the existing prompt-size gate. English, Spanish, and French recovery copy, the GM-first opening flow, and retry behavior have LiveView coverage.
- **Checks:** full WSL suite **334 tests, 0 failures**; three targeted LiveView scenarios **3 tests, 0 failures**; test-environment formatting, Gettext freshness, warnings-as-errors compilation, and `git diff --check` passed. Automated tests used isolated data and fake providers. Browser inspection was read-only; no resume, retry, or real provider request was performed.

## 2026-10-01 — Give account-limit recovery one clear owner

- The global account-pause banner is the only visible explanation of a ChatGPT usage limit. Removed the duplicate composer warning and repeated limit copy from the saved-turn status announcement; the retained action remains visible in the story without an extra warning card.
- Keep the same-turn Retry control beside the saved turn while the account pause is active, visibly disabled until the player resumes requests. Resume still only clears the pause; the player separately retries the saved turn or opening scene. A saved D20 result stays with that turn. When no global pause exists, the normal failure explanation and enabled retry behavior remain.
- LiveView behavior checks cover English, Spanish, and French; one visible limit explanation; preserved action; disabled and then enabled retry; no provider call on resume; opening-scene recovery; and saved-roll recovery. **Checks:** SessionLive **48 tests, 0 failures**; full WSL suite **338 tests, 0 failures**. Formatting, Gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. Tests use fake providers and isolated fixtures. No real provider request or live account action was performed.

## 2026-10-01 — Benchmark long-campaign context against full history

- This iteration operationalizes the product thesis reinforced by market research and captured in `IMPLEMENTATION_PLAN.md`: Storyteller owns durable campaign canon, while each GM request receives only relevant bounded context. Coherence and context cost are co-equal MVP acceptance goals.
- Added a deterministic 240-event campaign fixture and compared its full-history request size with the compiled request. The test requires the bounded request to be at least 5× smaller and within 2 KB of the equivalent 12-event campaign.
- The older Finca/Bodega staff commitment and newest event remain in GM context, while unrelated middle history is omitted. World, inventory, routes, place identities, character locations, and an active remote-character duty survive compaction. These measurements are serialized UTF-8 bytes plus request framing; they are a conservative proxy, not a tokenizer measurement. Real provider aggregate usage remains a separate runtime measurement.
- **Checks:** context-budget suite **13 tests, 0 failures**; full WSL suite **332 tests, 0 failures**; test-environment format, Gettext freshness, warnings-as-errors compilation, and `git diff --check` passed. No live provider or campaign database was used.

## 2026-10-01 — Retrieve seasonal campaign memories across paraphrased questions

- A player could preserve a commitment on the campaign board, then ask about it later using another season's common name (“fall” vs. “autumn”) and have the detail omitted from GM context. The local relevance vocabulary now connects fall/autumn, otoño, and automne with tasting/event phrasing and allocation terms such as earmark, reserve, and aside. With a paraphrased season, each topical cue in the question must also match; a shared season or generic event alone is too broad.
- Added a fake-provider, later-session behavior test for the autumn bottle reserve. The note reaches the GM when asked in English, Spanish, or French, while an unrelated bridge toll, same-season roof repair, and autumn fundraiser event stay out of context; each request remains within the configured input bound.
- The vocabulary remains curated and deterministic; this does not claim general semantic understanding. Broader paraphrase recall and false-inclusion coverage remain open MVP work.
- **Checks:** context-budget and story-memory suites **19 tests, 0 failures**; full WSL suite **332 tests, 0 failures**; format, Gettext freshness, warnings-as-errors test compilation, and `git diff --check` passed. Automated tests use isolated data and fake providers; no live provider or existing campaign was used.

## 2026-10-01 — Keep character voice guidance open while editing

- Browser testing exposed that entering one character voice note collapsed the nested voice section after LiveView updated, hiding the other fields while the user was still configuring the character. The section now stays expanded once any voice note has content, so quirks, accent/dialect, cadence, vocabulary, and mannerisms can be entered together. Empty optional sections remain collapsed.
- Added a LiveView behavior test that enters two separate voice fields across validation updates and verifies both values remain visible in the open section. A fresh fictional two-character campaign setup confirmed both distinct profiles appear in review and persist through campaign creation.
- The opening-scene request in that separate QA campaign reached ChatGPT but was rejected with an account usage limit. Storyteller saved the turn and paused requests across sessions; no retry or further provider request was made. Resume this live voice evaluation after usage becomes available.
- **Checks:** CampaignLive **19 tests, 0 failures**; format check and `git diff --check` passed.

## 2026-10-01 — Keep canonical continuity and context economy in one MVP gate

- Recorded the owner's market insight as Storyteller's leading product thesis: a model can retain a character's personality but lose campaign logistics as conversation context is compressed. In the vineyard example, the GM remembers employees well enough to give them dialogue but forgets that the Bodega is a forty-minute trip from the Finca. This is the concrete failure mode to prevent, not a claim that every competing product behaves this way. Added the same scenario as an explicit continuity-and-context-cost task in the product benchmark, while keeping vendor memory claims separate from observed behavior.
- The MVP response is algorithmic canon: the app owns and validates modeled places, presence, travel, duties, inventory, resources, and world time; the GM narrates and receives only the relevant bounded context for the turn. Character personality cannot stand in for where someone is or whether they can plausibly act there.
- Made continuity and context cost a single acceptance goal. Remaining work is called out for routine NPC availability, indirect and cross-language memory recall without false inclusion, and short/long synthetic campaign benchmarks comparing bounded requests with full-history baselines. Collect provider-reported aggregate usage where available; serialized bytes remain a conservative preflight proxy, not an exact token count. Required canon is never silently dropped to save context; if it cannot fit safely, fail recoverably.
- Documentation update only; no campaign state or application behavior changed in this entry.

## 2026-10-01 — Preserve distinct current-scene character voice guidance

- Added a context-budget regression with two colocated GM characters that have different quirks, accents, cadence, vocabulary, and mannerisms. When forced compaction runs, each present character keeps their own full voice profile while an unmentioned remote character's profile is omitted to conserve context.
- This proves the configured voice reaches the bounded prompt without being merged or discarded. It does not prove the model performs the voices distinctly; that still needs human evaluation in play with separate characters and several turns.
- **Checks:** context-budget suite **12 tests, 0 failures**; format check and `git diff --check` passed. Synthetic contexts and no provider call.

## 2026-10-01 — Keep character voice notes distinct and natural in GM context

- The GM policy now treats each `voice_guidance` as belonging to its character's speaker ID and name, forbids blending or swapping profiles, and asks for a few situational cues in natural dialogue. It explicitly discourages forced accents, phonetic spelling, stereotyped dialect, repeated catchphrases, and invented accents; GM narration keeps its own voice.
- A forced-compaction regression uses the shipped GM policy and verifies that two present characters retain their own names and full, distinct authored voice profiles, while an unrelated remote character's detailed profile is omitted. This validates prompt/context construction, not whether a model will perform distinct voices in generated play.
- **Checks:** ContextBudget **15 tests, 0 failures**; the ordinary observation prompt remains below the existing **10,000-byte** behavior ceiling. Full WSL suite: **338 tests, 0 failures**; formatting, Gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. No live provider or campaign data used.

## 2026-10-01 — Clarify time-passage turns and usage-limit recovery

- Time-passage timeline entries now use the player's “You” label, so a turn such as “An hour passes” reads as the player's action rather than a machine-generated request category. Stored event type and turn semantics are unchanged.
- The usage-limit recovery card explains the saved action and same-turn retry once for an initial failed turn, keeps the pending action visible, and offers one retry control after account requests resume. After a saved D20 roll, the card keeps the roll-specific retry explanation without repeating generic saved-action guidance. English, Spanish, and French are updated.
- **Checks:** SessionLive **47 tests, 0 failures**; locale LiveView **9 tests, 0 failures**; formatter, Gettext extraction freshness, and `git diff --check` passed. No live provider call or campaign UI interaction was used.

## 2026-10-01 — Enforce optional GM-character duties

- Existing and new GM characters can receive a named active duty tied to their canonical current place. The movement validator rejects a proposed departure even when a valid route and duration exist; same-place actions and unassigned characters remain unaffected. Duties can be renamed or released only through a reasoned, revision-checked, out-of-character authoring correction. Stale editors and unresolved turns cannot change the duty.
- The duty is stored on the character record, included in the GM's compact structured context, and retained by context compaction even for a remote character. It is omitted from player projections and story events. Irrelevant history/profile detail remains first to be compacted, and the full transcript is not re-sent on every turn; measurable cost remains the serialized request-byte bound and aggregate provider token usage when available.
- Recurring schedules, free-form calendar interpretation, and automatic duty completion are intentionally outside this slice. Campaigns without explicit active duties stay flexible.
- This is a concrete iteration on the product thesis recorded in the implementation plan: application-owned canon and validation should prevent the Finca/Bodega class of continuity error while compact context carries only the facts the GM needs. It does not claim general schedule interpretation or make the model infallible.
- Backup schema v9 exports/restores duty records and private authoring-audit snapshots; v1–v8 backups remain importable with no active duty. Migration `20261001000600` is applied to the local development database as a schema-only update; no campaign rows were rewritten. The campaign editor returned HTTP 200 for the separate fictional QA campaign and rendered the duty control. The previous continuity audit below describes the gap before this implementation.
- **Checks:** full WSL suite **328 tests, 0 failures**; Play behavior **75 tests, 0 failures**; campaign-authoring/context/editor **27 tests, 0 failures**; locale **9 tests, 0 failures**; backup **11 tests, 0 failures**. `mix format --check-formatted`, `MIX_ENV=test mix compile --warnings-as-errors`, Gettext freshness, and `git diff --check` passed. All automated cases use isolated data and fake providers; the active-duty scenario tests a 40-minute Finca/Bodega route without altering a live campaign or using a real provider.

## 2026-10-01 — Bound the current movement guarantee and track routine enforcement as MVP work

- A movement-domain audit confirmed that canonical place IDs, persisted routes, computed travel minutes, scene-presence validation, and cross-session tests prevent the original Finca/Bodega teleportation failure. Existing behavior coverage also rejects off-scene NPC dialogue/activity and movement from an unknown origin.
- The remaining gap is an employee whose route-valid departure contradicts an established duty: the app has no typed schedule or active assignment/release condition to check. Updated the implementation plan and acceptance brief to keep this explicit as open MVP continuity work; current location validation must not be described as routine-level enforcement.
- No campaign data, schema, or live provider was touched during this audit.

## 2026-10-01 — Retrieve durable wine memory across player languages

- A saved English wine-reserve note could be omitted when the player asked about the same fact using Spanish “vinos” or French “vins”: memory filtering compared exact meaningful words. The deterministic retrieval vocabulary now maps the explicitly equivalent forms `wine/wines`, `vino/vinos`, and `vin/vins` to one campaign concept.
- The alias applies only to player-managed public-memory relevance. Existing exact-word behavior, unrelated-note omission, GM-authored/private continuity, context byte bound, and older-event ranking are unchanged. This is a small curated vocabulary, not paid semantic search or general synonym expansion.
- The fake-provider play-turn regression asks in Spanish, captures the actual GM request, and verifies the reserve note is included, the bridge-toll note stays redacted, and canonical state plus both saved memories are unchanged.
- **Checks:** compiler tests passed (**10 tests, 0 failures**), Play behavior tests passed (**74 tests, 0 failures**), and the full WSL suite passed (**319 tests, 0 failures**). Warnings-as-errors test compilation, formatting, Gettext freshness, and `git diff --check` passed. No provider or live campaign was used.

## 2026-10-01 — Set GM characters' starting places in campaign setup

- The optional GM-character setup card now accepts a canonical starting place, and the review step shows it separately from character description and voice notes. Using the exact opening-location name colocates someone with the player; another name creates a separate public place without assuming a route. Leaving it blank keeps their location unknown instead of placing every NPC together.
- The starting place is persisted through the existing character/place initialization path, appears on the player board and in later-session GM context, and requires no schema change. Setup guidance and the field-specific length error are translated into Spanish and French.
- **Checks:** combined Play, campaign setup, SessionLive, and locale tests passed (**146 tests, 0 failures**) in WSL; the full WSL suite passed (**317 tests, 0 failures**). Warnings-as-errors compilation, format check, Gettext freshness, asset build, and `git diff --check` also passed. Coverage includes review/edit persistence, distinct vs omitted locations, visible location labels, later-session context, no fabricated route, and translated guidance. New behavior assertions use fake providers and isolated test data.

## 2026-10-01 — Show game time once per turn

- The story timeline now labels canonical date/time on the first public event of each turn, then repeats the label only if the canonical clock changes within that turn. This keeps fictional chronology available without repeating the same date and time on every GM or character bubble; real-world timestamps remain absent.
- The marker is computed across the accumulated timeline before splitting recent and earlier story, so session boundaries and loading older pages keep the correct first marker.
- **Checks:** focused SessionLive tests passed (**47 tests, 0 failures**), the combined Play, setup, SessionLive, and locale run passed (**146 tests, 0 failures**), and the full WSL suite passed (**317 tests, 0 failures**). Warnings-as-errors compilation, format check, Gettext freshness, asset build, and `git diff --check` passed.

## 2026-10-01 — Repair public characters with an unknown location

- Campaign care can now select a public GM-controlled character whose canonical location is missing, so players can repair an incomplete starting state without allowing the GM to invent a zero-time move from an unknown origin. The existing location correction still requires a known public destination and a reason, is revision-checked, records before/after audit snapshots, and does not create a story event or advance game time.
- Characters located in GM-private places remain excluded from correction targets, and non-nil locations that are not public are not treated as unknown. After correction, the assigned public place is included in later-session GM context.
- **Checks:** `MIX_ENV=test mix test test/storyteller/play_test.exs --max-cases 16` passed (**73 tests, 0 failures**); `MIX_ENV=test mix test test/storyteller_web/live/session_live_test.exs --max-cases 8` passed (**45 tests, 0 failures**); warnings-as-errors compilation, `mix format --check-formatted`, and `git diff --check` passed in WSL. Only isolated fixtures and fake providers are used; no live campaign or provider is accessed.

## 2026-10-01 — Reject free placement from an unknown origin

- Tightened canonical movement validation so an established character whose current place is unknown cannot move to any destination at zero minutes. The same-proposal character-creation IDs are explicitly authorized for first placement; the trusted opening-scene intent also authorizes initially unplaced setup characters (including the player). Known same-place moves remain zero-minute no-ops, while known cross-place moves still require a graph route and add its computed time.
- Added pure coverage distinguishing existing unknown-origin characters from same-proposal creations and a fake-provider behavior regression proving a pre-existing unplaced NPC cannot be moved into the player's scene to speak or act. The behavioral case asserts validation failure, unchanged canonical location and elapsed world time, and no timeline events for that turn.
- Updated the MVP acceptance criteria to preserve the opening-scene exception and cover unknown-origin NPC movement explicitly. This does not add schedule, motive, or availability modeling; route-valid spontaneous movement remains a separate continuity limitation.
- **Checks:** full WSL suite passed (**312 tests, 0 failures** with `--max-cases 16` to fit the local PostgreSQL connection limit); focused Play and TravelGraph suites also passed (**81 tests, 0 failures**); the 45-test LiveView suite passed; `MIX_ENV=test mix compile --warnings-as-errors`, `mix format --check-formatted`, and `git diff --check` passed. New behavior regressions use isolated test campaigns and fake providers. No development or live campaign was accessed, and no provider was called.

## 2026-10-01 — Anchor older context to the current scene

- Older-event retrieval now considers the current place's nearest connected-place names and stable speaker IDs for up to 32 GM-controlled characters in the scene, alongside a separately capped set of player-action terms. Common English, Spanish, and French function words are filtered from search and ranking so names such as “The Copper Stag,” “La Casa,” or “Les Cèdres” do not match unrelated history. It uses only the existing local campaign graph and event store; no provider or external search call was added. Candidate older events remain capped at 40, and the compiler still selects at most eight relevant older conversation events within the existing context byte ceiling.
- The context compiler now uses the same connected-place names and scene speaker IDs when ranking older events after database retrieval. A fake-provider cross-session behavior test establishes older Bodega narration and a scene NPC promise, asks about next steps indirectly from the Finca, and verifies both facts arrive while older unrelated history is omitted and the request stays within its configured bound.
- This is deterministic lexical/entity-anchor retrieval, not general semantic or synonym search. It only reaches a Bodega fact when the canonical graph connects that place to the current scene and the old event text names the place, or when a scene NPC authored the event. Facts still need structured canon or discoverable stored evidence; availability/routine constraints are not added here.
- **Checks:** full WSL suite **311 tests, 0 failures**, including the focused Play and context-budget suites (**81 tests, 0 failures**); warnings-as-errors test compilation, formatting, Gettext freshness, and `git diff --check` passed. The regression uses a fake provider and synthetic cross-session events only; there was no live provider request and no real campaign was accessed.

## 2026-10-01 — Correct the current world's date, time, or weather in place

- Extended **Campaign care** with a correction path for the currently visible public date, time, and weather, so a setup typo can be repaired after a campaign has begun. Each correction is reasoned and revision-checked, updates the player board and future GM context, and remains separate from narration and the in-world event timeline.
- Date/time corrections re-anchor the elapsed-world clock at its existing total; weather corrections leave all clock fields alone. The picker and receipt use the same canonical public value as the board, and a correction removes stale legacy aliases that could otherwise override it. In-flight turns and stale forms still reject atomically.
- Bumped campaign backups to schema v8 for world-label audit records. v1–v7 imports remain supported, while a v7 backup cannot claim a v8 world correction. The migration only expands the existing audit-kind constraint.
- **Checks:** full WSL suite **311 tests, 0 failures**; the focused LiveView/domain/backup set passed (**50 tests, 0 failures**); warnings-as-errors compilation, formatting, Gettext freshness, and `git diff --check` passed. The development migration applied successfully and the local home page returned HTTP 200. Tests used fake providers and `storyteller_test`; the development change was schema-only. No campaign rows or Vineyard data were edited, and no live provider call was made.

## 2026-10-01 — Make algorithmic continuity the MVP's defining advantage

- The implementation plan now treats Storyteller-owned world state as the product thesis: the LLM narrates and proposes, while the application persists modeled facts, checks presence and other constraints, and commits accepted changes with provenance. This is a release goal, not an assumption that a longer prompt will make model memory reliable.
- The context budget is part of that same goal. Keep the full campaign locally, assemble each request from the current scene and relevant canonical facts or older evidence, omit unrelated prose first, and preserve required canon. Measure aggregate provider usage when available; use the byte ceiling only as a preflight proxy. If required canon cannot fit, explain the retryable limit instead of asking the GM to guess.
- Added behavioral coverage for campaign-specific state across later sessions: a vineyard uses its own cash and wine ledgers, a dungeon uses player-carried items without inheriting vineyard data, a 1567 campaign keeps its free-form historical date, and a genre without configured resources or mechanics can still play normally. These complement the Finca–Bodega presence/travel acceptance test already listed in the plan.
- **Checks:** genre-flexibility coverage passed within the full WSL suite (**305 tests, 0 failures**); `mix format --check-formatted` and `git diff --check` passed. These cases use fake providers and isolated test campaigns. No live provider request or real campaign was used.
- **Separate live QA:** In the fictional Dunvegan QA campaign, one ordinary in-game question completed successfully through the connected ChatGPT-plan flow. The action stayed visible while the GM responded; the employer was introduced through narration and character dialogue, then appeared beside Douglas in the current-scene roster. This single turn confirms the basic live interaction and current-scene placement only; it does not validate cross-session recall or token savings. The accessibility tree also exposed the visually hidden `New story` screen-reader announcement; it was not a visible card or chat message and belongs with the deferred V1 accessibility review. The Vineyard campaign was not accessed, and no campaign text, prompt, or private context was added to the repository.

## 2026-10-01 — Spend context on relevant memory and avoid duplicate scene answers

- A context-budget review found that public player-managed memories were sent in full whenever an ordinary request fit the byte ceiling, even if a note had nothing to do with the current action. The deterministic compiler now includes note details only when meaningful words overlap with the player's action, present characters, or current place. Unrelated notes keep stable identity/status metadata and are marked in `context_completeness`; the full note remains visible on the campaign board. GM-authored public continuity and GM-private canon are not altered. This lexical selection is a low-cost baseline; synonym-heavy and implicit-reference retrieval still needs scenario coverage.
- The same change adds a fake-provider cross-session regression: an asked-about note reaches the GM with complete detail, an unrelated note's title/details stay out of context while remaining on the board, and an under-budget request remains within the conservative input bound. A companion compiler case proves unrelated detail is filtered even when the unfiltered request already fits.
- The product benchmark in `docs/PRODUCT_BENCHMARK.md` compares the public descriptions of Friends & Fables and LegendKeeper and applies Apple's feedback/progressive-disclosure/motion guidance. It labels vendor claims separately from Storyteller's isolated QA observation and does not claim hands-on competitor testing. The near-term gameplay action is useful, non-repetitive look-around answers; general maps, tactical grids and multiplayer are deferred.
- **Checks:** full WSL suite **302 tests, 0 failures**; `mix format --check-formatted`, `mix gettext.extract --check-up-to-date`, `MIX_ENV=test mix compile --warnings-as-errors`, and `git diff --check` passed. No live provider request or Vineyard campaign access was used for this iteration.

## 2026-10-01 — Make follow-up scene questions useful without replaying the board

- Read-only review of the separate fictional QA campaign found a follow-up question answered with a repeated world-bar detail and a near-copy of the current-situation panel. Ask GM now instructs the GM to treat the board and recent narration as already known, answer the precise question from the character's current public vantage, and avoid echoing the scene or its previous answer.
- For another look-around, give at most one supported new detail. If none is grounded in context, say so briefly and return choice with a low-pressure invitation to inspect something specific or choose a next move. Do not manufacture clues, objects, sounds, people, or events for color. A direct question still leaves time and canon unchanged.
- Added a fake-provider regression that opens a canonical scene, asks the same follow-up from it, checks the question-specific instructions and supplied location/question context, and verifies the world, presence, and clock remain unchanged. No live provider request or Vineyard campaign access was used.
- **Checks:** `PlayTest` **72 tests, 0 failures**; the changed Elixir files are formatted and `git diff --check` passed. The later repository-wide formatter check passed after the concurrent context-budget test was formatted. The regression uses only a fake provider.

## 2026-10-01 — Keep durable public story memory within the token budget

- The defining product idea is now captured as an MVP gate: the application owns durable campaign canon and plausibility; the LLM narrates and proposes changes but cannot replace structured world state or be expected to recall a growing transcript. The Finca–Bodega example remains the concrete acceptance test for presence and travel.
- A read-only review of the separate QA campaign found the campaign-memory board empty even though the story had established durable facts. Added a player-managed public-memory path as a small backstop for facts that lack typed ledger fields. Notes can be added, edited, and retracted out of character; each change is revision-checked and reasoned, with before/after audit history. It creates no fictional timeline event and does not advance the in-world clock.
- Player-managed entries are immutable to GM continuity proposals. The prompt identifies them as protected, and proposal validation rejects edits/retractions algorithmically. They persist on the board and in relevant GM context across sessions even when a fake provider returns no continuity changes. The board limits the player to eight active notes of at most 300 characters; the context-budget regression keeps all eight under the default 24,000-byte preflight bound.
- Added the cross-session Finca/Bodega behavior test: a 40-minute route connects the distinct places, the employee remains at the Finca when the player arrives at the Bodega, and remote dialogue/activity are rejected until the employee travels.
- Campaign backup schema v7 exports/imports player-memory entries and their nullable event provenance. v1-v6 backups remain supported; a v6 file cannot claim v7-only player-memory features. The additive migration `20261001000400` is applied to the local development database without rewriting campaign rows. QA browser review opened the editor read-only; no note or GM turn was submitted, and the Vineyard campaign was not accessed.
- **Checks:** full WSL suite **300 tests, 0 failures**; focused memory/context/backup/LiveView suites **66 tests, 0 failures**; post-contrast SessionLive rerun **44 tests, 0 failures**; `mix format --check-formatted`, `mix gettext.extract --check-up-to-date`, `MIX_ENV=test mix compile --warnings-as-errors`, and `git diff --check` passed. A development-environment warnings-as-errors invocation collided with the intentionally running local Phoenix server's loaded modules; the isolated test-environment check passed.

## 2026-10-01 — Correct tracked public canon without rewriting play

- Added an out-of-character correction panel to the active session for repairing a public inventory item, a typed public campaign resource, or a character's known public location. Each change requires a reason and shows a concise receipt outside the story timeline with its target and before/after values.
- Corrections apply atomically to canonical state and create a separate durable audit record with target, before/after snapshot, expected revision, and reason. They do not add story events or advance game time. Subsequent sessions and GM context use the corrected records.
- The form offers only player-safe public targets; hidden locations and GM-private records do not leak through target options or audit snapshots. Revision checks reject stale forms, and corrections are refused during pending, resolving, or awaiting-roll turns to prevent races with prebuilt GM context. A failed turn remains correctable before retry.
- Campaign backup schema v6 exports and validates correction audit records while preserving v1-v5 import compatibility. The additive `20261001000300` migration is covered by the isolated test database and was subsequently applied to the development database as a schema-only change; no campaign rows were rewritten.
- **Checks:** full WSL suite **288 tests, 0 failures**; focused receipt LiveView test passed; JavaScript tests **13/13**; asset build, `mix format --check-formatted`, `mix compile --warnings-as-errors`, Gettext extraction freshness, and `git diff --check` passed. Automated tests use `storyteller_test` and fake providers.

## 2026-10-01 — Reopen the authorized QA retry check after migration

- The first subagent check found the local UI blocked by the pending correction migration, so it did not retry or call the provider. After applying the additive migration, `/campaigns/35/sessions/36` loaded successfully and rendered the current scene and normal composer.
- Read-only state inspection found the originally reported turn 19 is `superseded` with its safe `proposal_validation` stage retained; turns 22–24 are completed and there is no currently failed turn. The page has no failed-turn card or Retry control. The subagent did not replay turn 19 or a completed turn, and made no provider call.
- Campaign 34/Vineyard was not accessed. The only database change was creation of the correction audit table and its indexes/constraints.

## 2026-10-01 — Anchor fresh campaigns in canonical places

- The continuity goal is now enforced at campaign start: a fresh opening response must leave the player in a known or newly created public place. A public NPC who speaks or acts in that scene must also have an accepted placement there. A rejected proposal leaves the timeline and campaign state untouched.
- The test provider now establishes a deterministic public opening place when a fixture has no configured start. Existing campaign setups with a known public start keep that place without duplicating it. Movement fixtures use the seeded place's canonical stable ID, matching how the real GM receives it in context.
- This closes a specific start-of-play hole in the broader MVP continuity promise: all future plausibility checks need a trustworthy initial location, while context remains compact and backed by durable records rather than requiring the model to infer geography from chat.
- **Checks:** both opening-scene `PlayTest` cases passed; `SessionLiveTest` passed (43 tests, 0 failures); the full WSL suite passed (290 tests, 0 failures). `mix format --check-formatted`, `mix gettext.extract --check-up-to-date`, `mix compile --warnings-as-errors`, and `git diff --check` passed. The development database's additive canon-correction migration was applied without changing campaign records.

## 2026-10-01 — Product goal: algorithmic continuity within a deliberate token budget

- Recorded the user's market-research insight as a defining MVP goal: campaign coherence must come from Storyteller's durable, validated world model, not from asking the GM model to remember an ever-growing chat transcript. The forty-minute Finca–Bodega journey remains the concrete acceptance scenario: staff cannot be casually present across town unless modeled movement or another established contact explains it.
- Clarified the guarantee boundary: structured locations, routes, presence, inventory, resources, dates, and other modeled facts can be enforced and carried forward. Unmodeled details remain uncertain; the LLM is a narrator and proposal generator, and only valid application-checked proposals change canon.
- Made context efficiency part of the same MVP promise and release gate as consistency. Keep full history persisted locally, retrieve relevant older evidence, prioritize current and private canon, compact irrelevant prose, preflight requests against a conservative byte bound, and use aggregate provider usage where available. Each iteration must test that relevant older canon survives while unrelated history does not push an ordinary request beyond its bound. Never silently discard required facts or equate bytes with exact tokens.
- A manual QA question in the separate fictional campaign exposed a normal-turn failure at 27 saved events: preflight rejected the request before inference because the fixed GM policy used too much of the 24,000-byte budget. This iteration shortens the policy by 34.6%, preserves every active continuity detail during compaction, and adds a fake-provider regression proving an ordinary Ask GM request reaches inference under the default bound.
- **Verified:** retrying that same saved look-around in QA campaign 35/session 36 completed through the connected ChatGPT-plan route. It returned one concise answer, left the in-world date/time, weather, location, inventory, and presence unchanged, and displayed the recovery guidance only once before retry. This used one plan-usage GM request; no API key billing or Vineyard data was involved.
- **Checks:** combined context-budget, Play, and SessionLive suites **109 tests, 0 failures**; full WSL suite **279 tests, 0 failures**; `mix format --check-formatted`, `mix compile --warnings-as-errors`, Gettext extraction freshness, and `git diff --check` pass. Tests use fictional fixtures and `storyteller_test`; the one live turn used only the separate QA campaign.

## 2026-10-01 — Persist elapsed world time from validated movement

- Added a durable campaign elapsed-minute total and an exact free-form date/time anchor. Accepted movements advance by at least the normalized route duration supplied by the server. Consecutive legs sum for each character, while concurrent journeys share elapsed time using the longest character total.
- `time_advance_minutes` now means the proposed total duration for a turn, inclusive of travel. The server commits the larger of that bounded model value and canonical route floor, preventing a narrated 40-minute trip from becoming 80 minutes. Time passage requires a positive total; Ask GM requires zero. Rejected proposals and provider failures cannot advance the clock.
- The GM receives the elapsed ledger, the board shows a compact localized elapsed cue below the existing time label, and accepted free-form date/time changes re-anchor that cue. No fantasy label parsing or automatic date rollover is performed; “First watch” remains an exact label.
- Campaign backup schema v5 exports the clock and imports v1-v4 with elapsed minutes defaulted to zero, anchoring only to exact existing public labels. Additive migration `20261001000200_add_elapsed_world_clock` is applied only to `storyteller_test` for verification; no campaign database or live provider was used.
- **Checks:** pending focused Play, backup, and LiveView tests, Gettext extraction freshness, and warnings-as-errors compilation.

## 2026-10-01 — Build the GM's context from canon within a safe input bound

- Made the continuity compiler a first-class MVP goal: Storyteller is responsible for durable world state and plausibility; the LLM provides narration and proposes changes that the application checks. The vineyard's forty-minute Finca–Bodega trip is the example regression scenario: people stay where the ledger says they are until an accepted movement or other modeled explanation changes that.
- Added a deterministic context compiler that keeps the full campaign history in PostgreSQL, preserves canonical world/inventory/travel/objective facts, compacts unrelated old prose and off-scene profile detail first, marks omitted older context, and errors safely if the required payload still cannot fit. It retrieves up to 40 older conversation events by action and current-scene terms, beyond the most recent 40 events.
- Set a 24,000 conservative input bound for supported OAuth models. Before provider usage is known, the compiler bounds the UTF-8 serialized instructions/context plus framing; successful Responses completion usage reports authoritative aggregate input/output counts. Section diagnostics are byte sizes only. The separate OAuth `input_tokens` counting endpoint returned `401 hardened_oauth_rule_missing` during a synthetic capability probe; no campaign data was sent. Exact per-section token counts are therefore still an open measurement improvement.
- Failed preflight keeps the player's submitted turn retryable and records only numeric size metrics. The model never receives local metrics, telemetry has no campaign IDs or text, and the existing public projection continues to keep GM-private data hidden.
- **Checked:** full WSL suite passed (275 tests, 0 failures) with `--max-cases 8`; formatting, warnings-as-errors compilation, Gettext freshness, and `git diff --check` passed. Focused coverage includes long unrelated history, relevant older facts, required-canon overflow, numeric-only metrics, provider usage parsing, and retrying the same saved action. Tests used `storyteller_test` and fake providers; no live model request was made.

## 2026-10-01 — Recheck the authorized stuck-turn investigation

- Inspected only QA campaign 35/session 36. The previously reported target turn 19 is now `superseded`, with 22 attempts, `proposal_validation` as the retained failure stage, and no committed events. A later turn 22 and turn 23 completed normally; there are no currently failed turns. I exercised `retry_turn(19)` once with a guard provider: it returned unchanged, made no provider call, and did not alter the stored turn. The normal retry handler correctly excludes a superseded turn. The current database cannot establish whether the Retry control was missing when the original report was made.
- **Follow-up implemented:** superseding a failed turn changes its lifecycle status while retaining its safe failure code and stage. A regression test covers a proposal-validation failure; stale turns remain non-retryable and no provider content is exposed. The inspection and test used no changes to this campaign's story or world state.

## 2026-10-01 — Persist travel routes and validate scene presence

- Implemented campaign-scoped place connections with canonical integer-minute durations, public/GM-private visibility, and concise scene relevance. A normalized shortest route is computed from stored connections; model-supplied travel time is not trusted. Same-turn place/connection discovery can support a first arrival when the accepted proposal contains a valid route.
- Character movement and public NPC dialogue/activity are checked against canonical current/final presence. A character who remains at the finca cannot casually appear at a bodega forty minutes away; an accepted move, including an explicit same-turn arrival, updates presence and records the computed route duration. Unplaced newly introduced characters need an explicit canonical arrival before public speech or activity.
- GM context receives relevant local connections and bounded route summaries, while GM-private route details stay in hidden context. The route/presence slice did not parse free-form date/time; the separate elapsed-clock slice below records canonical route minutes without altering those labels.
- Campaign backup schema v4 includes place connections and retains v1-v3 import compatibility; legacy backups default to no modeled connections. The true v3 regression fixture preserves its historical `failure_stage` field while checking that legacy routes default empty.
- **Defining product promise:** structured local canon prevents LLM memory drift, while a deliberate context budget controls request cost. Cross-session state continuity and a measured/configured per-model input bound are required acceptance checks. The first compiler and aggregate provider-usage instrumentation are tracked in the 2026-10-01 context-compiler entry above; exact per-section tokenizer counts remain open.
- Behavioral integration coverage now includes a 40-minute Finca→Bodega transition and next-turn context, rejection of an off-scene NPC, explicit same-turn NPC arrival, first-visit route creation, and v1-v3 backup imports. Focused WSL checks passed (88 tests, 0 failures), the full suite passed (266 tests, 0 failures), and the session LiveView module passed (40 tests, 0 failures). Warnings-as-errors compilation, formatting, and `git diff --check` passed. The additive route migration ran against `storyteller_dev` without modifying campaign records. Tests use fake providers; OAuth validation tests use generated local keys and fake OIDC endpoints. No live AI was used.

## 2026-09-30 — Make algorithmic world consistency a core MVP goal

- Storyteller's continuity should come from its durable, structured world model rather than expecting an LLM to remember every detail from prose. The MVP now explicitly calls for modeled place connections and travel durations, canonical character locations/presence, accepted movement, and relevant scene context for the GM.
- Added the finca/bodega regression scenario: if travel takes forty minutes and employees remain at the finca, they cannot appear at the bodega without an accepted move or established way to communicate. Their presence must persist across turns and sessions.
- Added a token-budget goal: construct a bounded, relevance-ranked prompt; retain the full canon/history in the database; retrieve relevant old facts by stable references; measure token counts by context section without logging prompts or private values. Large unrelated history must not cause unbounded prompt growth or hide important facts.
- Updated `IMPLEMENTATION_PLAN.md` and `UX_ACCEPTANCE.md`. The original entry recorded the goal before route/presence validation shipped; those protections and behavioral tests are now implemented in the 2026-10-01 travel slice. The subsequently added elapsed clock is tracked above, and exact per-section tokenizer measurement remains open.

## 2026-09-30 — Recover abandoned GM turns and retain safe failure diagnostics

- Each failed turn now retains one fixed diagnostic stage: context assembly, provider call, response decoding, proposal validation, or commit. The application stores no exception text, prompt, private context, credential, or raw model output in this field. Campaign backup schema version 3 preserves the stage while older v1/v2 backups remain importable.
- The session LiveView monitors its GM task. If a task exits after claiming a turn, only that still-current attempt is marked as a retryable failure; stale attempts cannot overwrite a newer retry. If a worker remains resolving past its 120-second claim lease, the page can reclaim the turn with attempt fencing. This keeps retries available in the same view and avoids silently running the same player action twice.
- **Live retry investigation:** campaign 35/session 36 turn 19 was failed with `invalid_response` at 17 attempts. A fresh page showed an enabled retry; the first authorized retry preserved the saved turn, entered the responding state, and failed again at 18 attempts. After stage diagnostics were installed, one further UI retry produced `failure_stage: proposal_validation`, confirming that a response reached local proposal validation and was rejected; the earlier attempt's cause remains unrecoverable. The persisted attempt counter now reads 21, three higher than the last recorded value despite one click. I did not retry again; the counter discrepancy needs investigation before more live calls.
- **Competitor task benchmark:** added an official-source comparison of scene orientation, flexible inventory, canon correction, and campaign resume in [the product benchmark](PRODUCT_BENCHMARK_2026-09.md). This is desk research with explicit evidence limits, not timed or authenticated usability testing.
- **Checks:** full WSL ExUnit suite **249 tests, 0 failures**; focused Play, SessionLive, and CampaignBackup suites passed (**55**, **39**, and **7** tests). Formatting, warnings-as-errors compilation, and `git diff --check` pass. Tests use fake providers and isolated `storyteller_test`. The additive `20260930001400` migration was applied to `storyteller_dev` to verify stage capture in campaign 35; aside from the authorized retry's turn status/attempt/diagnostic fields, no canonical state or story events changed. Vineyard was not accessed.

## 2026-09-30 — Keep observation replies novel and audit failed-turn retry

- The GM policy now limits “look around” and “what can I see?” replies to new or specifically inspected details from the player's vantage. When there is nothing new, the GM should say so briefly and return control. The two helpful prompts now make that expectation clear in English, Spanish, and French.
- **Hands-on play check:** the separate Amber Orchard QA campaign returned one short line — “Nothing new or out of place catches your eye from here.” — without repeating the weather, location, or established scene. The scene panel updated; game time and inventory stayed unchanged. No Vineyard campaign was opened or changed.
- **Retry investigation:** campaign 35/session 36's turn 19 was failed with `invalid_response`; the campaign and session are active and ChatGPT plan requests are not paused. A fresh page showed an enabled **Retry this turn** button. One click transitioned to “The game master is responding,” then returned to the failure card; the persisted turn stayed failed with 18 attempts (up from 17). Code review found that `invalid_response` collapses provider, decoding, proposal-validation, and commit failures, while the turn record retains only the normalized code and attempt count. The cause of this turn's repeated failures cannot be recovered from stored data. Add sanitized stage-level diagnostics without storing raw model output. A stale `worker_turn_id` could still block recovery in the original LiveView, but that path was not reproduced. No second retry was made and no other campaign was accessed.
- **Checks:** regression assertion confirms observation instructions reach the GM provider request. The full WSL suite passed (**244 tests, 0 failures**); JavaScript tests passed (**6/6**); format, gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` passed.

## 2026-09-30 — Keep campaign backup tools in campaign persistence

- Removed import and export controls from the campaign library. The library now stays focused on creating, opening, resuming, and archiving stories.
- Moved import into a collapsed **Campaign persistence** section at the bottom of the library and kept export in the same collapsed section below sessions on campaign details. Restore remains available on a fresh install, while neither action competes with create/resume.
- Kept the detail-page action labeled **Edit campaign**, so it describes the complete editor instead of emphasizing character voice guidance.
- Prevented facts written for GM-controlled characters while they are in a GM-private place from later entering public character panels or receipts when they return to public play. The facts remain available in hidden GM context; an explicit structured public update can disclose a fact later.
- Reordered the active MVP queue around complete play tasks and state trust. Backup is implemented maintenance with no further MVP feature work planned; accessibility hardening remains V1 and other AI providers remain V2.
- **Hands-on play check:** in the separate Amber Orchard QA session, one move ate an apple and asked Inés what she planned next. The GM delivered one concise narration followed by one direct character reply; the story did not gain a state-update message. Inventory moved from 3 apples to 2, and both the turn and count persisted after reloading.
- **Checks:** latest campaign and backup placement tests **18 tests, 0 failures**; full suite **243 tests, 0 failures**; JavaScript tests **13/13**; formatting, gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. The full suite uses fake providers and the isolated `storyteller_test` database.

## 2026-09-30 — Guide campaign setup and surface canonical change receipts

- Campaign creation is now a four-step wizard for story, player character, starting scene, and optional people/details, followed by a review step. Backtracking preserves every entered value; validation returns to the step that needs attention. Optional setup groups remain skippable, and successful creation still opens the new campaign.
- Public place and character changes now have collapsed “Last changed” receipts beside their relevant board cards. Receipts come from accepted state-change events and show safe before/after values, a grounded reason when available, and in-world time. GM-private locations and character changes are excluded, and receipts do not add system messages to the story.
- **Checks:** full WSL suite **241 tests, 0 failures**; JavaScript tests **13/13**; format check, gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. Automated tests use `storyteller_test` and fake providers; no live AI call or Vineyard campaign mutation was made.

## 2026-09-30 — Keep campaign maintenance secondary and protect time-passage agency

- The campaign detail action uses the broad **Edit campaign** label. Backup/restore hierarchy has since been refined; see the latest feature log entry.
- Campaign setup corrections now save their reason and before/after state atomically, require a reason only for actual changes, and remain separate from prior story entries. Player-facing correction history lists safe categories and omits any correction containing GM-private facts or voice guidance. Backup format v2 carries this audit history and imports both v1 and v2 files.
- A time-passage response is rejected if it speaks/acts for, moves, updates, or requests a roll from the player's character. Explicit multi-day duration remains intact. The **Wait here** nudge uses the current canonical location and asks the GM to stop at the next meaningful decision.
- Additive migration `20260930001300_create_campaign_authoring_corrections` adds the correction-history table; it has been applied to the persistent development database without changing campaign rows.
- **Checks:** full WSL suite **236 tests, 0 failures**; JavaScript tests **13/13**; format check, gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. Automated tests use fake providers and `storyteller_test`; no real provider request was made.

## 2026-09-30 — Separate player identity and soften AI-limit recovery

- Campaign creation and editing now collect the player's character name separately from the description. Review and campaign detail show both; campaign cards and the session header use the name alone. The full description remains part of the character profile and GM context. An additive migration conservatively backfills names only where a legacy value clearly begins with a short name followed by a comma; ambiguous text stays intact as the description.
- A ChatGPT account usage limit now reads as a temporary GM pause within the play screen. The notice says the GM cannot answer while account usage is unavailable, links to Usage settings, and explains that resuming does not send a turn. The saved player action and any D20 result remain on the same turn, with an explicit retry after the player resumes requests. The copy treats this as a service limit rather than fictional “energy”; it does not imply a reset time or fall back to paid API calls. English, Spanish, and French copy is covered.
- **Checks:** full WSL suite **228 tests, 0 failures**; JavaScript tests **13/13**; format check, gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. Tests use fake providers and `storyteller_test`; no live model call was made.

## 2026-09-30 — Fold voice cues into character setup and extend MVP goals

- The campaign editor now groups GM-only quirks, accent/dialect, cadence, vocabulary, and mannerisms inside each character's own setup card, alongside their visible facts and GM-only notes. The initial campaign form already follows this per-character layout.
- Added MVP requirements for distinct player-character name and description fields (the name alone headlines the character list) and for a gentle, recoverable response to AI usage limits that preserves the pending action and any roll without disguising a service limit as fictional “energy.”
- **Checks:** full WSL suite **226 tests, 0 failures**; focused inventory and campaign-authoring scenarios pass. JavaScript tests **13/13**. Formatting, gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. Tests use fictional fixtures and the isolated `storyteller_test` database; no live provider request was made.

## 2026-09-30 — Persist character voice guidance and edit campaign setup

- GM-character setup captures separate private voice notes for quirks, accent/dialect, cadence, vocabulary, and mannerisms. Each field is capped at 280 characters and a character's notes at 1,200 characters; these notes are stored apart from public facts.
- Campaign detail pages link to an editor for title, premise, setting, tone, narration language, the current player-character description, existing GM-character public/private facts, and voice notes. Voice and mannerism notes now sit within the corresponding character setup card rather than in a separate section. Saving updates current projections for future turns and leaves prior sessions and story entries intact. A reversible migration adds the private voice-note field.
- Added behavioral tests for setup validation, public-projection privacy, rejected model writes, and edit-history preservation.

## 2026-09-30 — Add character identity and GM-led play goals

- Added MVP requirements for character-specific voice notes (quirks, optional accent, cadence, vocabulary, and mannerisms) that persist and inform future GM prompts without reducing a character to a caricature.
- Added post-creation campaign editing and explicit, auditable out-of-character canon corrections so a player can repair mistakes without losing campaign history.
- Added distinct **Act or say** and **Ask the GM** interaction goals plus contextual look, wait, and pass-time nudges. Direct questions should clarify the current scene without advancing time or canon; chosen time passage should invite the GM to move the world forward and pause at the next meaningful player decision.
- **Checks:** Product requirements and behavior scenarios recorded in `IMPLEMENTATION_PLAN.md` and the checkpoint. Documentation-only update; application behavior is not yet implemented for these goals.

## 2026-09-30 — Back up campaigns safely and speed up action entry

- Added a versioned, sensitive campaign backup. Downloads preserve each session, canonical public and GM-private state, inventory, panels, continuity records, rolls, turns, and ordered event history. The export reads from one repeatable database snapshot; imports validate the complete file and record references before atomically restoring it as a new campaign. Interrupted in-flight turns become retryable failures, and OAuth credentials are outside the export path.
- The campaign library accepts one bounded JSON backup and makes the separate-copy behavior and private GM contents clear. Downloads are attachments marked private/no-store. Import rejects unknown fields, unsupported versions, oversized files, invalid ownership/references, and credential-shaped additions.
- Added Ctrl+Enter submission through the same form flow as Send; plain Enter remains a newline, including in multiline dialogue. Added setup-wizard and GM-first opening-scene outcomes to the product plan and checkpoint for the next gameplay iteration.
- **Checks:** full WSL suite **215 tests, 0 failures**; backup-focused round-trip, malformed-file, atomic rollback, controller, and 501-session portability tests pass. Composer/timeline/panel JavaScript tests **13/13**. Format, warnings-as-errors compile, gettext freshness, asset build, and `git diff --check` pass. Tests use fictional fixtures and `storyteller_test`; no live provider or campaign data was changed.
- **Read-only local smoke:** the fresh production-style transaction exported the separate Amber Orchard QA campaign successfully (27,964 bytes). The JSON stayed in memory; no campaign records, OAuth store, or files were changed.

## 2026-09-30 — Reaffirm open-source and bring-your-own-GPT release scope

- Clarified the staged account model: V1 is a polished, MIT-licensed, locally run open-source app whose operator connects their own eligible GPT/ChatGPT account from Settings using the supported plan-usage OAuth flow. No shared project credential or secrets in Git; document eligibility, limits, setup, backup/recovery, upgrades, disconnect, and credential handling before the V1 release.
- V2 is reserved for other AI providers, with each provider's connection and billing path decided explicitly. The plan does not promise support for unverified GPT account types or silently fall back to API billing.
- Recorded campaign backup/export and restore as an MVP trust feature: versioned, sensitive campaign-only backups; validate before atomic import into a new campaign; preserve canon and event provenance; exclude the OAuth token store. Whole-install recovery instructions remain part of V1.
- **Checks:** Documentation-only update; no application behavior or campaign data changed.

## 2026-09-30 — Inspect recent tracked-resource changes in place

- Added a collapsed “Last changed” detail beside each changed public resource. It shows the accepted before/after, the change reason, and its in-world time, without adding another entry to the story. The projection reads only recent public state-change events and current public resource keys; private panel changes never appear.
- Extended the private-text guard to public panel-change reasons before they are recorded, so the new receipt cannot expose an exact GM-private phrase.
- **Checks:** Play and SessionLive focused suites **76 tests, 0 failures**; full WSL suite **205 tests, 0 failures**; JavaScript tests **10/10**. Formatting, gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. SessionLive coverage confirms the receipt is collapsed, sits beside the updated value, and omits a private panel seed.

## 2026-09-30 — Simplify character setup and guard exact private facts

- Campaign setup now generates stable GM character IDs from names, handles duplicate and reserved names, and keeps those implementation IDs off both the setup form and review screen. The player can focus on character identity and role instead of inventing database-like speaker keys; English, Spanish, and French catalogs were refreshed.
- Added a deterministic guard that rejects exact normalized GM-private phrases in public narration, character dialogue/activity, public panel-change reasons, and the public memory summary used in later GM context. It checks private character/place facts and names, inventory, objectives, continuity entries, and campaign panels; accepted public state can explicitly disclose a phrase. One-word facts under eight characters and entity names under five characters are ignored to limit false positives. Semantic paraphrases are not detected, so scenario review remains necessary.
- **Checks:** Full WSL suite **205 tests, 0 failures**; focused setup LiveView suite **11/11**; focused private-fact suite **5/5**; JavaScript tests **10/10**. Format, gettext freshness, warnings-as-errors compile, asset build, and `git diff --check` pass. Tests use the isolated test database and fake provider. No live AI request or QA-campaign mutation was made.

## 2026-09-30 — Put the campaign first and ground scenes in visual cues

- Moved the interface-language control from the always-visible global header into a collapsed Settings menu, translated as **Ajustes** and **Paramètres**. Removed repeated campaign-title and narration-language metadata from the active session header while keeping the setting and player character visible.
- Added a small original SVG scene cue that combines time of day with recognized weather, including a moon, cloud, and mist for midnight fog. English, Spanish, and French terms are normalized and matched as whole words; unrecognized conditions use a neutral cue. The text weather remains authoritative beside the image.
- Softened new story-entry motion to a low-distance 420ms arrival while retaining the 520ms beat pacing and existing reduced-motion behavior. The GM policy now avoids repeating unchanged world indicators and includes only relevant character dialogue/activity.
- Added MVP acceptance for information relevance and restrained atmospheric cues. Recorded the release path: owner-run GPT MVP; V1 open-source local setup, own GPT-account connection, privacy/secrets documentation, and deferred accessibility review; V2 additional AI providers. Local environment/secret files are now ignored. The README remains deferred until V1.
- **Checks:** Full WSL test suite **199 tests, 0 failures**; JavaScript tests **10/10**; format, gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass. The separate QA route returned HTTP 200 and rendered the closed Settings disclosure, removed metadata, and scene cue. No turn was submitted or campaign data changed. The account's GPT-plan pause remains in place, so no live-provider response was attempted. A local scan for common high-confidence credential formats found no matches in Git history or the current workspace.

## 2026-09-30 — Confirm tabletop conversation as an additive product goal

- Added an explicit product goal alongside the original campaign, gameplay, continuity, accessibility, and design goals: make play feel like a shared tabletop conversation.
- Clarified acceptance: story entries are player actions, natural GM narration, direct character dialogue, and relevant roll prompts; a turn should feel coherent rather than arriving as four or five abrupt, disjointed messages. State and memory remain in their panels, and introductions and world changes stay in the scene narration.
- This records the direction already reflected in the play UX requirements; no application behavior changed in this documentation update.

## 2026-09-30 — Protect hidden character state and make inventory shortcuts reliable

- Canonical character places now determine presence and location. Legacy location aliases are removed from character facts and world prompts, and the GM cannot write location through character facts.
- Characters at GM-private places are omitted from the player's scene projection. Their introductions, dialogue, activity, and fact-update events stay out of the public timeline and their hidden activity is cleared; later GM context retains the private event history. Public world location follows the player's canonical public place rather than stale snapshot text.
- Inventory “Use in your action” buttons now send the server-composed sentence directly to the composer hook. The editable draft is preserved when another action is added; enabled inputs receive focus at the end, while a disabled input can still display the suggestion without attempting focus.
- An incomplete LiveView textarea change payload is ignored safely. This prevents the composer from crashing when the browser reports a change without an input value.
- Browser QA on **QA Playtest · The Amber Orchard** confirmed “Use Amber apples in your action” populated the composer. ChatGPT-plan requests were already paused, so the textarea was disabled and did not take focus. The page was reloaded afterward to clear this QA-only draft; no turn was submitted, campaign records were not modified, and the account-wide pause remains unchanged.
- Refreshed `docs/PRODUCT_BENCHMARK_2026-09.md` with the current vendor-stated baseline, sourced opportunities, and explicit desk-research limits. Hands-on competitor task comparison remains open.
- Refreshed the optional API-billing comparison using current GPT-6 Luna rates and the app's one-call/roll-follow-up flow. `docs/INFERENCE_COST_INVESTIGATION_2026-09.md` records the token assumptions, unmeasured usage gap, and cost-optimization ideas to defer until the MVP works; no model, prompt, request, or billing behavior changed.
- **Checks:** Full WSL suite **197 tests, 0 failures**; focused SessionLive suite **28 tests, 0 failures** after tightening push-event assertions; action composer, story timeline, and panel pulse JavaScript tests **10/10**. Formatting, gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass.
- **Privacy limit:** Structured event and projection filtering cannot guarantee that free-form public GM narration will never paraphrase a hidden secret. Review this through scenario testing as the campaign experience grows.

## 2026-09-30 — Keep turn replies readable and the desktop board in place

- A newly saved player action now appears in the campaign story immediately while the GM resolves it, survives reconnect/reload, and disappears as a preview when its canonical event arrives. This keeps the player's own message visible during slow responses without duplicating it.
- New GM narration, NPC dialogue/activity, and world changes arrive one beat at a time at 520ms intervals with a brief entrance animation. A visible “Show all new messages” control catches the player up; reduced-motion preference reveals the response immediately, and existing history does not replay on mount. Assistive technology gets one concise live announcement per event.
- Loading older campaign history preserves the reader's scroll anchor. The story region opens at the latest post and follows new events only when already at the bottom.
- Roomy desktop play uses a fixed viewport board: the story timeline is the only active vertical scroller, while the composer and scenario rail stay in place. The rail keeps location, current situation, tracked resources, and two actionable inventory rows visible; full narration remains in history, with detailed scene, inventory, objective, memory, and roster content available in accessible disclosures. Smaller viewports retain document scrolling to keep controls reachable.
- Added Spanish and French labels for the new player-facing disclosures and inventory “see more” control. Campaign-authored story and item names remain unchanged.
- Live browser QA on the separate Amber Orchard campaign at 1396×1244 confirmed the document is fixed, the story has independent overflow, the 927px world rail fits without overflow, and the hidden reveal controls are not displayed. A 390×844 check confirmed the mobile layout remains reachable and scrolls normally. No turn was submitted.
- Read-only local route benchmark: five GETs each for `/`, `/campaigns/34`, and `/campaigns/34/sessions/35`; all returned 200. Medians were 0.645s, 0.624s, and 0.665s. The local sample includes Windows-to-WSL forwarding and is not a production performance target.
- **Checks:** Full WSL suite **196 tests, 0 failures**; warnings-as-errors compile, format, gettext freshness, asset build, and `git diff --check` pass. The standalone timeline tests pass **4/4**. The development schema reports all migrations up, including `20260930000900_create_play_continuity_entries`.
- Scene image pacing remains an open integration: Plus OAuth does not generate images. When a local or user-provided image source is selected, image cards should share the same reveal queue; no paid API image usage was added.

## 2026-09-30 — Make the story a tabletop conversation and move state cues to panels

- Player-facing story pagination now includes player actions, GM narration, character dialogue, and D20 prompts/results. Character activity and structured state-change audit events remain durable but no longer appear as transcript messages.
- The GM policy now favors one coherent scene beat, natural introductions and weather/date narration, and character activity on the character panel. Behavioral tests verify new-character dialogue and narration, updated canonical panels, and retained audit records without system-style chat entries.
- World details, tracked resources, memory, objectives, scene facts, inventory, and character panels now watch displayed values and use a restrained gold pulse when those values change. Each changed panel has a concise localized polite announcement, and reduced-motion preference disables the animation.
- Read-only browser review of the separate Amber Orchard QA campaign confirms the visible transcript is limited to the player's actions, GM narration, direct character speech, and roll interaction. No turn was submitted during this review.
- **Checks:** Full WSL suite **196 tests, 0 failures**; story-timeline and panel-pulse JavaScript tests **6/6**; formatting, gettext freshness, warnings-as-errors compile, asset build, and `git diff --check` pass. A screen-reader session and live change-pulse interaction remain manual QA follow-ups. Scene-image pacing still depends on a local or player-supplied image source.

## 2026-09-30 — Persist campaign continuity beyond model summaries

- Added a campaign-scoped continuity ledger for durable facts, relationships, and commitments that do not belong in the existing objective, inventory, place, character-fact, or campaign-panel ledgers. Entries have stable IDs, a kind, public or GM-private visibility, active/resolved/retracted status, and same-campaign source-event provenance for both their introduction and latest update.
- GM-proposed creates and updates are bounded, reasoned, validated against the existing ledger, and committed in the accepted turn transaction. Kind and visibility are immutable; closed entries cannot be reopened or recreated under a previously used ID. Invalid batches leave the turn's canonical state and timeline unchanged. Each campaign retains at most 100 entries total and 80 active entries; entry details are limited to 500 characters so GM context stays bounded.
- Active and terminal entries are included in later-session GM context with their visibility, status, and latest source event sequence. The public projection includes only active public entries. Public timeline pages show only the latest source event for a public entry, including a resolution or retraction with no reason; earlier snapshots are suppressed. GM-private entries and their event history stay off all player surfaces.
- Tightened the GM writing policy to make each response one coherent, concise beat, use NPC dialogue/activity when it adds something to the moment, skip filler and repeated behavior, and return control clearly without omitting canonical changes or the in-world date.
- **Prompt-quality observation:** manual review of the separate QA campaign noted repeated latch/awning descriptions. The writing guidance now directly addresses repetition; subsequent gameplay review should confirm it improves output without dropping relevant state changes.
- **Behavioral coverage:** Play tests verify stable source-event provenance, cross-session context, survival beyond the 40-event window, public/private isolation, latest-event-only public timeline output including a reason-free terminal update, immutable visibility, same-ID recreation rejection, the record cap, and all-or-nothing rollback. The coordinated final suite and build checks are recorded in the latest checkpoint entry.

## 2026-09-30 — Keep story reading in place and show the game clock

- Made the story panel its own keyboard-scrollable region with a bounded height and contained overscroll. It opens at the newest post, follows new messages only while the player is already at the bottom, and preserves an upward reading position while earlier history is loaded. The scenario rail stays sticky and scrollable on wide screens.
- Story events now store a public in-world date/time snapshot. A player's action uses the clock before resolution; the GM narration and its response use the resulting clock. Hidden events receive no public clock snapshot. Message labels now show the campaign date and time without a real-world UTC suffix.
- Older events did not store an in-world clock, so their misleading UTC labels are removed and no fictional times are inferred. Migration `20260930000800_add_game_time_to_play_events` adds nullable event metadata for new turns.
- **Checked:** the date/time LiveView scenario verifies a player action at 09:15 and a GM reply at 09:20, private-event exclusion, and Spanish/French labels. Browser review confirmed PageUp scrolled the story panel while the page and sticky scenario rail stayed in place. Full suite: **180 tests, 0 failures**; formatting, gettext freshness, warnings-as-errors compilation, asset build, and `git diff --check` pass in WSL.

## 2026-09-30 — Resolve the local GPT gameplay blocker

- Fixed two causes that prevented the locally connected ChatGPT plan from resolving a game turn: Responses streaming emits `response.output_text.delta` before its terminal event, which the adapter was not collecting; and a fresh Phoenix process checked the provider callback before loading its module. The adapter now accumulates bounded streamed text, and gameplay loads the provider before checking its callback.
- Provider diagnostics now record the failing stage, safe error code/parameter, HTTP status, and request ID while omitting player actions, campaign context, and credentials.
- **Live check:** after the ChatGPT-plan connection returned an available model catalog, a Responses stream returned text and the saved Amber Orchard QA action completed through the local game flow. The LiveView showed GM narration and Inés's dialogue; the canonical inventory and world facts remained intact. This used the separate fictional QA campaign at `/campaigns/34/sessions/35`; the Vineyard campaign was not opened or changed. No API key, API billing, or optional usage reset was used.
- **Checked:** focused Play and OpenAI provider suites pass (**51 tests, 0 failures**). Full-suite and release checks are recorded in the checkpoint after completion.

## 2026-09-30 — Complete ChatGPT connection and check live inference

- The local Connect page now reports ChatGPT plan usage connected after the account owner completed OAuth consent. An authenticated `/v1/models` request returned five models for the selected account.
- The first minimal `/v1/responses` smoke attempt was blocked with the recognized usage-limit error. A later smoke request and complete QA turn are verified in the entry above. Plus usage is shared with other ChatGPT apps; no reset time is inferred. Check ChatGPT Usage settings if another usage limit occurs.
- At this earlier checkpoint, the separate Amber Orchard QA session still held its saved, unresolved test action. It was later resolved without involving the Vineyard campaign.

## 2026-09-30 — Restore the ChatGPT connection redirect

- Fixed the default HTTP path that prevented OAuth provider discovery. In Elixir `nil` is an atom, so the default adapter guard called `nil.request/1` instead of Req; nil now selects Req before the generic module clause. A network-free Req.Test regression test covers the default branch.
- The OAuth loopback callback now follows the production listener's `PORT`, and the validator accepts configured loopback ports while preserving the fixed callback path. Authorization and code exchange continue to use the same exact URI.
- Provider-issued dynamic client IDs are persisted in the protected local store before code exchange. A failed exchange, `invalid_grant`, or declined direct-plan scope retains the ID for a later sign-in; older credential files derive their registration from existing credentials.
- **Checked:** Focused Connect-controller, HTTP, OAuth, and TokenStore suites pass (**27 tests, 0 failures**). A real metadata lookup and CSRF-protected POST to the local Connect form returned a 302 to `auth.openai.com` with the expected authorization fields. Tests cover the translated handoff guidance, retry after exchange failure, `invalid_grant`, and declined scope, restart persistence, legacy credentials, and active-account binding. The provider consent page was not opened; no account consent, token exchange, or live inference was performed.

## 2026-09-30 — Pause plan requests account-wide after a usage limit

- Only the recognized provider usage-limit error latches a pause in the protected TokenStore file. It persists across app restarts and blocks new GM requests across campaigns and sessions; generic provider errors do not latch it. A clear or account disconnect removes the pause, and existing credentials remain compatible with the new optional state field.
- The pause banner links to ChatGPT Usage settings and offers an explicit “Resume requests” action. Resume only clears the pause; it does not call the provider. A saved failed turn remains available for a separate manual retry, including its accepted D20 result. A limited retry latches the pause again. No API-key or API-credit fallback was added, and the UI does not assume a reset time.
- **Checked:** Focused TokenStore and SessionLive suites: **29 tests, 0 failures**; WSL warnings-as-errors compile and gettext extraction freshness check pass. Fake-provider tests cover a generic failure, cross-session blocking, resume without a provider request, re-latching, file restart, legacy-file compatibility, and after-roll recovery. All test database behavior uses `storyteller_test`.

## 2026-09-30 — Announce turn status without rereading panels

- Added one always-mounted polite, atomic status region for turn progress, roll requests, recorded after-roll results, recoverable failures/retries, and completion transitions. Conditional status panels no longer each define their own live region; the story timeline keeps its additions-only announcement behavior. A completed turn is announced only when this LiveView connection observes the turn leave the open state, so reconnecting does not announce old history as new.
- **Checked:** Focused SessionLive suite: **19 tests, 0 failures**; WSL format check and `git diff --check` pass. Behavior covers pending/resolving, awaited roll, recorded result, failed/retry, localized completion, and no replay on reconnect. Keyboard focus retention when Send becomes unavailable remains a manual check; no automatic focus movement was added.

## 2026-09-30 — Make plan-limit and admission recovery precise

- Generic HTTP 403 admission/policy failures now remain provider errors; only the explicit plan-sharing ineligibility code is shown as an ineligible account. This avoids unnecessary reconnect guidance for unrelated 403 responses.
- Usage-limit guidance tells the player to wait for the allowance to reset, keeps the same action and D20 result available, and labels the retry accordingly in English, Spanish, and French. The account page no longer claims a global play pause. Storyteller still has no API-key or API-credit fallback.
- **Checked:** fake-provider coverage distinguishes generic 403 responses from explicit ineligibility. SessionLive behavior verifies localized usage-limit guidance and retry labels. Full WSL suite: **161 tests, 0 failures**; format check, warnings-as-errors compile, asset build, and `git diff --check` pass.
- **Known limitation:** the allowance gate is per failed turn, not account-wide. A player can manually submit from another session while the provider reports the shared account limit; those requests still use the ChatGPT-plan route and never fall back to paid API billing. Review an account-wide pause once the provider's reset/recovery behavior is confirmed.

## 2026-09-30 — Put the current situation on the scene board

- The current-place card now leads with the player's location and shows the latest public GM narration as the current situation, followed by place details and present characters. It updates on the next public narration and provides a localized empty state. The copy is sourced from public timeline events, so GM-private context stays out of the player board.
- **Checked:** SessionLive behavior verifies empty state, latest narration replacing the prior situation while both remain in the story, Spanish/French strings, and private-text exclusion. Read-only 370px browser review of Amber Orchard confirms the place-first order and dark card contrast. No game turn was submitted. Full WSL suite: **158 tests, 0 failures**; format, warnings-as-errors compilation, asset build, and `git diff --check` pass.

## 2026-09-30 — Make D20 turn recovery explicit

- Failed turns now retain the provider failure reason and saved player action. Before a roll, the player sees that the saved action remains unresolved and retry resumes the same turn. After a player roll, the saved result is shown and retry is described as continuing with that result.
- **Checked:** Play behavior covers a provider timeout after a recorded D20: retry reuses the saved result and creates each action/roll event and state change once. SessionLive behavior covers the failure panel, saved result, same-turn retry, and pre-roll reconnect guidance. Spanish and French recovery copy is included; the full suite passes (**158 tests, 0 failures**).

## 2026-09-30 — Refresh the product comparison notes

- Updated the desk research with the current distinction between Friends & Fables and Craft, Kanka's flexible per-entry inventory and dashboard tradeoffs, and LegendKeeper's map/wiki focus. The notes make clear that no competitor campaign was played and no usability ranking is claimed.
- **Checked:** Claims link to official product documentation and are marked as vendor descriptions; account creation and terms acceptance were not attempted.

## 2026-09-30 — Keep campaign setup focused

- Collapsed the four optional setup groups when empty and labeled each “Optional” in the summary. Adding a player fact, starting item, GM character, or campaign-panel field opens its section immediately, keeping the main setup path compact while preserving a clear path to flexible campaign configuration.
- **Checked:** LiveView behavior confirms the sections start collapsed, open when populated, and close again when the last row is removed. English, Spanish, and French labels are covered; mobile browser review confirms the 370px layout is scannable. Full suite, format, warnings-as-errors compilation, and asset build passed in WSL.

## 2026-09-30 — Restore contrast for shared form labels

- Mapped the shared zinc text utilities to the tabletop palette and tuned stone-colored hover states for dark surfaces. Form labels, helper text, reusable table headings, and secondary action buttons now keep readable contrast across rest, hover, and focus states.
- **Checked:** campaign setup screenshot at 370px confirmed visible labels and helper text; interactive review verified the add-detail button keeps a dark background and readable label on hover. Page and viewport width remained aligned. WSL asset build passed.

## 2026-09-30 — Keep the campaign premise close during play

- Added a native collapsed disclosure near the session header so the player can reopen the campaign's premise without leaving the active session. The premise remains user-authored and is not added to each timeline entry.
- **Checked:** SessionLive behavior test confirms the disclosure label, collapsed default, and saved premise content. In the isolated Amber Orchard session, Enter opened the disclosure, exposed the saved premise, and collapsed it again without leaving play.

## 2026-09-30 — Make active sessions easy to resume

- Campaign details now offer a prominent direct link back to the active session. When starting another session will complete it, the page says so and explains that the full story remains saved.
- **Checked:** CampaignLive behavior verifies the resume destination, completion warning, and “Start another session” label; starting it preserves the previous session as completed. Locale tests cover the new copy in English, Spanish, and French.

## 2026-09-30 — Keep mobile scene context in one place

- The sticky scene shortcut now points to the current place card, which already contains its surroundings and the people present. Removed the duplicate world-state card that repeated date, time, weather, and location from the compact header.
- **Checked:** SessionLive behavior tests verify one scene destination, a single rendered time value, and the absence of the duplicate card. Read-only browser review uses the fictional Amber Orchard campaign.

## 2026-09-30 — Jump straight to the mobile turn composer

- The sticky session bar begins with a “Your turn” link on playable sessions. It focuses the labeled composer and offsets it below the sticky bar; completed/read-only sessions have no dead composer link.
- **Checked:** LiveView behavior tests cover the focusable target and navigation link. At a 370px browser viewport, keyboard Enter activated the link, focused the composer, and kept the board within viewport width. Visual review also confirmed the translucent amber and white card surfaces stay dark and readable.

## 2026-09-30 — Keep date and time canonical in GM context

- Public world aliases for date, time, and weather now normalize to one canonical key before storage and again when older state is read. Legacy conflicts use the latest matching public state-change event value (or the existing field precedence when history has no matching update); multiple aliases for one fact in a single proposal are rejected. Accepted updates reconcile legacy state before applying the new value.
- The GM request and player-facing board now see the same single date/time/weather values, so old data cannot present one time in the header and another in the scene facts.
- **Checked:** focused Play and SessionLive suites pass (**49 tests, 0 failures**). Behavioral coverage verifies that the latest event value wins over stale persisted aliases, the value appears once on the board and in GM context, newer updates survive reconciliation, state heals to one canonical field, and conflicting aliases in one proposal fail atomically. Isolated `storyteller_test`, fake providers only.

## 2026-09-30 — Preserve dark card contrast on narrow screens

- Added dark palette mappings for translucent amber and white utility backgrounds used by campaign commitments, current-place cards, and nested people/objective rows.
- Darkened amber action colors so cream button labels meet the 4.5:1 contrast target in normal and hover states.
- **Checked:** read-only 370px viewport review confirmed those card surfaces remain dark and readable. The sampled Send action measures 5.13:1 at rest and 4.65:1 on hover. This was a targeted spot check; full contrast and assistive-technology reviews remain open.

## 2026-09-30 — Keep multi-step player travel canonical

- When a turn records multiple player movements, the public world location now uses the final destination, matching the player's persisted current place.
- **Checked:** a behavioral regression verifies final place and world location agree in public projection and in the next session's GM context. It is included in the focused Play and SessionLive run (**49 tests, 0 failures**).

## 2026-09-30 — Page through earlier campaign story

- The campaign timeline starts with a bounded 500-event recent window and exposes a localized “Load earlier story” action for preceding public events. Cursor and DOM identity use immutable event sequence values, so page loads are ordered and idempotent.
- Previously loaded pages remain visible when LiveView refreshes for a new turn. The latest 20 entries stay in the polite additions-only live region; fetched history stays outside it, so reviewing old entries is not announced as new story. Earlier-session markers are computed in one linear pass across loaded history.
- **Checked:** focused Play and SessionLive suites pass (**45 tests, 0 failures**) and the full suite passes (**147 tests, 0 failures**). Tests cover sequence-cursor ordering, 1,101 events across two sessions, repeated loads without duplicates, session headings, and a refresh that appends new activity without dropping loaded pages. WSL formatting, warnings-as-errors compilation, asset build, gettext extraction/merges, and `git diff --check` pass.

## 2026-09-30 — Make campaign resource changes transactional

- Replaced absolute panel-value proposals with strict typed operations: signed deltas for quantity and money, typed sets for text/status/date, and a required grounded reason for every change.
- The commit transaction locks the campaign panel rows, calculates numeric results from the canonical current values, rejects negative balances and no-ops, then persists the new value together with visibility-scoped before/change/after audit events.
- The session timeline shows each resource label, before/after values, delta or set, unit, and reason. Public history omits GM-private panel operations; the GM receives the updated values in later-session context.
- Updated GM policy, checkpoint, and UX acceptance criteria. Reading or reviewing a ledger alone must leave its values unchanged.
- **Checked:** Play, Panels, and SessionLive focused suites **47 tests, 0 failures**; full WSL suite **145 tests, 0 failures**. WSL format check, warnings-as-errors compile, asset build, and `git diff --check` passed. Extracted English keys and merged translated Spanish/French labels. All tests used the isolated `storyteller_test` database and fake providers; no campaign rows were touched.

## 2026-09-30 — Responsive session section shortcuts

- Added a compact sticky in-page navigation bar on narrow session layouts for the scene, current place, campaign story, and inventory. Public objectives and tracked resources appear as shortcuts only when those sections contain public data; the desktop two-column layout stays unchanged.
- Native fragment links move focus to their section targets. The targets have visible keyboard focus treatment and scroll spacing below the sticky bar. The navigation name and reused section labels are available in English, Spanish, and French.
- **Checked:** focused SessionLive suite **11 tests, 0 failures**; full suite **142 tests, 0 failures**; WSL format check, warnings-as-errors compilation, asset build, `git diff --check`, and Spanish/French catalog merges passed.

## 2026-09-30 — Introduce new GM characters during play

- GM proposals can create stable GM-controlled character IDs with public and GM-private facts. The same proposal may let a newly created character speak, act, receive an item, move to a known or newly created place, or receive a fact update.
- Character IDs, facts, owners, speakers, and places are validated before the existing locked commit transaction. New character records are inserted before same-turn dialogue, activity, and location events, so the first encounter remains atomic with its public and GM-private audit entries.
- Public projections and audit events include only names, visible facts, public items, and public presence. GM-private character facts and hidden places and presence remain in GM context and private history across sessions.
- Updated the GM policy, proposal shape, introduction timeline entry, and this checkpoint. No database migration is needed.
- **Checked:** Play behavior tests pass (30 tests, 0 failures), and SessionLive tests pass (9 tests, 0 failures). Coverage includes introduce-and-speak, public presence, hidden-fact and hidden-place continuity across sessions, atomic rejection of duplicate IDs and unknown or malformed place references, and player-visible introduction rendering without private facts. Format check, warnings-as-errors compilation, asset build, and `git diff --check` pass in WSL. No migration was needed.

## 2026-09-30 — Keep roll targets in the story timeline

- Roll-request timeline entries now show the test plus any specified difficulty and target. Players can still see what a D20 result was judged against after resolution or reconnect.
- **Checked:** the SessionLive behavior test checks the request details while awaiting a roll and after reopening the completed session. The display reuses the existing translated labels; no translation catalog or migration change was needed.

## 2026-09-30 — Refresh sourced product benchmark

- Rechecked official Friends & Fables, Craft, Kanka, and LegendKeeper feature pages. The notes now describe the current advertised play and campaign-management features, distinguish those vendor claims from verified behavior, and avoid treating the products as interchangeable.
- Added a consistent hands-on task protocol covering first play, scene/resource discovery, inventory/resource changes, cross-session continuity, recovery, and private facts. No product usability ranking is claimed before those tasks are performed.
- **Checked:** source links point to the official product pages; interactive competitor testing remains outstanding.
- Captured a local request-response baseline for the campaign library, campaign detail, and fictional QA play session: five HTTP 200 GETs per route, with medians of 0.734s, 0.736s, and 0.758s. These development measurements include Windows-to-WSL localhost forwarding and are not a production target.

## 2026-09-30 — Keep inventory canon inside the turn loop

- Decided against direct player writes to canonical inventory in the single-player MVP. Item use, transfers, consumption, and resource changes go through the normal action composer and GM-validated proposals, preserving the story reason and audit trail for accepted changes.
- Reconsider a separate correction request only if playtesting shows the normal action flow cannot reliably resolve mistakes; no player-facing inventory edit screen is planned now.

## 2026-09-30 — Accessible story timeline updates

- Kept the chronological story list mounted from the empty state and marked it as a polite, additions-only live region with non-atomic updates. The first and later appended events can be announced without repeating existing history.
- **Checked:** SessionLive tests verify the live-region attributes on the rendered campaign timeline; the focused suite passes (8 tests, 0 failures). Manual assistive-technology review remains outstanding.

## 2026-09-30 — Genre-flexible resource trade scenario

- Added a fictional Amber Orchard behavior scenario where the GM consumes one basket of produce and increases a typed cash balance in the same turn. The next session's GM context and the public projection both retain the remaining stock and updated cash.
- This tests fungible campaign resources alongside item inventory without using vineyard campaign data.
- **Checked:** the focused Play suite passes (27 tests, 0 failures); full `mix test` passes (136 tests, 0 failures). Format, warnings-as-errors compilation, asset build, and `git diff --check` pass in WSL.

## 2026-09-30 — Amber Orchard D20 playtest

- Exercised a second session in the separate fictional QA campaign with a fake provider. The GM asked for a D20 against target 12; the player's click recorded 16 once, after which the GM completed the turn with dialogue and visible activity.
- A later malformed fake-provider response failed without adding turn events. Retrying the saved action completed once, with one player-action event and one narration event.
- **Checked:** public timeline contains the accepted result, the session page returns HTTP 200 with the resolution, and the GM-private character fact and campaign panel note are absent from player HTML. No live model or OAuth call was made.

## 2026-09-30 — In-play player character details

- GM proposals may add or revise the player's flexible public `visible_facts` when the action establishes a durable detail. Existing unrelated facts stay intact; player updates require a concise action-grounded reason and cannot write GM-private player facts or overwrite name, identity, description, or canonical location keys.
- Player fact patches apply atomically with the turn and create a public audit event containing only the patch and reason. The timeline identifies the character-detail update and explains its reason. GM-controlled characters keep their existing split public/private fact updates.
- Updated the GM policy and proposal shape, and refreshed the product benchmark's remaining-gaps list. Spanish and French timeline labels and reason copy are translated.
- **Checked:** focused Play and SessionLive suites pass (34 tests, 0 failures), covering public updates, later-session context, board rendering, reasoned audit history, private/missing-reason/unknown-ID/identity rejection, rollback, and existing GM-character updates. Full `mix test` passes (136 tests, 0 failures).

## 2026-09-30 — Flexible player character details in campaign setup

- Campaign setup accepts up to 50 optional player-visible label/value details, with bounded labels and values and case-insensitive duplicate-label rejection. These flexible facts are stored alongside the existing player-character description; no RPG-specific fields or migration were added.
- The setup review shows the selected details before creating the campaign. The existing player character projection feeds them into the player board and GM context. Setup copy and validation messages are translated in Spanish and French.
- **Checked:** focused Campaigns and CampaignLive setup suites pass (24 tests, 0 failures), including setup-to-facts-to-board/context persistence and invalid, oversized, and duplicate rows. The focused Campaigns, CampaignLive, and LocaleLive run passes (30 tests, 0 failures), including Spanish and French row labels/placeholders. Format check, warnings-as-errors compile, asset build, and diff check pass in WSL.

## 2026-09-30 — Readable item details and canonical location

- The inventory disclosure now renders generic properties as escaped key/value rows, with humanized nested paths and compact map/list values. It retains a native keyboard-accessible disclosure.
- The play-board location rail now prefers the player's canonical current place over a stale world-location string.
- **Checked:** the session LiveView suite passes (7 tests, 0 failures), including nested properties, escaped values, and a regression test for a stale location string. Full `mix test` passes (132 tests, 0 failures); formatting, warnings-as-errors compilation, asset build, and `git diff --check` pass in WSL.

## 2026-09-30 — Safe item property updates

- Added a GM-proposed `update` operation limited to an existing item's flexible `properties` map. Nested objects merge recursively, preserving unrelated keys and enforcing the same JSON depth and node limits on the merged result.
- Updates preserve stable item identity and all other canonical item fields. They validate sequentially with add, transfer, and consume operations; any later invalid operation rejects the full proposal before inventory changes or audit events commit.
- Audit visibility follows the item: public updates appear in public history without the GM's reason, while private update details and reasons stay in GM-private history. Canonical model context carries the updated properties into later turns and sessions.
- Updated the GM policy and operation schema with the properties-only rule.
- The player board displays changed properties in its readable item-details disclosure.
- **Checked:** focused inventory domain and Play behavior suites pass (44 tests, 0 failures). Focused formatting, warnings-as-errors compilation, `mix assets.build`, and `git diff --check` pass in WSL.

## 2026-09-30 — Inventory actions from the play board

- Added a localized action button to public player- and party-owned inventory items. It appends a short item-use sentence in the campaign narration language, preserves the current composer draft, and focuses the textarea for review and editing.
- The server only uses item data found in the session's public inventory projection and silently ignores hidden, unknown, or NPC-owned item IDs. The player still submits the normal turn explicitly; the button does not change inventory or create a turn.
- **Checked:** focused session LiveView tests pass (6 tests, 0 failures), covering all three narration languages, interface-language independence, draft append/edit behavior, ownership filtering, forged IDs, and no inventory or timeline mutation before submission. `mix format` passed.

## 2026-09-30 — Campaign objectives and story commitments

- Added an optional campaign-scoped objective ledger with stable IDs, open/completed/abandoned status, public or GM-private visibility, and no delete path. Objectives remain canonical when a new session starts.
- GM context now includes the public and private objective lists, and policy discourages completing goals without established evidence. The provider can propose ordered, reasoned create/update operations; validation checks each operation against current and prior proposed state, rejects duplicate or unknown IDs, and applies valid batches atomically with the turn.
- Objective audit events retain full snapshots and reasons in private history. Public projections and timeline events contain only public objective snapshots, while the play board groups public objectives by status and provides Spanish/French UI labels.
- **Checked:** focused Play and locale LiveView suites pass (27 tests, 0 failures), and the full suite passes (120 tests, 0 failures). Behavioral tests cover ordered create/update snapshots, status progression across sessions, private context versus public projection/history, invalid ordering, duplicate IDs, and all-or-nothing rollback. `mix format --check-formatted`, `mix compile --warnings-as-errors`, and `mix assets.build` pass. Migration `20260930000700` was applied to the persistent development database through WSL `mix ecto.migrate`.

## 2026-09-30 — Partial inventory transfers and proposal recovery

- Added quantity-aware transfers: a partial stack keeps its existing stable ID and remainder, while the moved quantity becomes a new stack with copied properties and visibility. Whole-stack transfer event shape remains compatible.
- GM instructions now explain split identity and conservation. Invalid inventory proposals map to the normal `invalid_response` recovery state instead of being mislabeled as provider failures.
- **Checked:** domain and end-to-end behavior tests cover valid split ownership, properties, quantity conservation, stack limits, public audit payloads, and all-or-nothing rejection when a later operation over-consumes the remainder. `mix test` passed (117 tests, 0 failures).

## 2026-09-30 — Canonical places and character presence

- Added durable, campaign-scoped place records with stable IDs, descriptions, flexible surroundings, and public or GM-private visibility. A campaign's starting location becomes the player's initial place; explicitly visible character locations seed known NPC presence.
- GM prompts now receive the public and hidden place lists plus each character's canonical current place. Location changes must create a place before moving someone, use a known character and destination, and keep the player out of GM-private places.
- Accepted place creation and movement apply in the same transaction as the turn. Public projections and timeline events omit private places and private character locations. Generic world changes can no longer teleport a character or overwrite the canonical location.
- Added a player-board scene card for the current place, surroundings, and people there; character cards show a known location, and public travel events appear in the story timeline.
- Added a second idempotent fictional QA seed, **The Amber Orchard**, configured with an orchard starting scene, an NPC at a separate known place, flexible stock panels, and player-owned equipment. The earlier Observatory QA campaign is left untouched.
- **Checked:** behavior tests cover seeded player/NPC locations, public movement, private vault isolation from projection and history, rejected free-form teleportation, and continuity into another session. The full WSL suite passed (110 tests, 0 failures); Spanish and French play-board labels render in locale tests.

## 2026-09-30 — Campaign inventory and continuity

- Added optional starting items to the reviewed campaign setup, with a name, quantity, unit, category, and description. Items begin in the player's public inventory; the item structure also supports stable IDs, campaign-defined JSON properties, party/NPC ownership, and GM-private visibility.
- Added explicit GM-proposed add, whole- or partial-stack transfer, and consume operations. Validation rejects unknown items/owners, duplicate IDs, malformed properties, and over-consumption. Inventory mutations apply atomically with the turn and append visibility-scoped timeline events; general world changes cannot overwrite the inventory ledger.
- Added canonical public/GM-private inventory to each GM prompt and a player-facing board for known items. Public projections and public events omit hidden items and internal operation reasons. Campaign panels remain the place for fungible balances such as vineyard cash and stock quantities.
- **Checked:** starting inventory campaign-setup tests, inventory domain tests, and end-to-end play tests cover public/private visibility, item ownership, consumption, invalid mutations, narration without an accepted inventory operation, and continuity into another session. Full-suite and UI build checks are recorded in `docs/CHECKPOINT_2026-09-30.md`.

## 2026-09-29 — Product priorities: player board, inventory, and continuity

- Rebalanced the product plan around useful play, not appearance alone: the player should see where they are, what is happening, and what their character owns or controls.
- Added a campaign-flexible inventory and resource direction for distinct dungeon items as well as vineyard cash, wine, and vine stock. Required changes must be canonical, validated, accepted once, and traceable to campaign events.
- Documented the current gap: prompt construction already includes hidden GM context and bounded history summaries, but there are no first-class owned-item or location records. Generic fact maps and scalar panels do not enforce item identity, transfers, or NPC presence.
- Added an initial sourced desk benchmark of Friends & Fables, Kanka, LegendKeeper, and Apple's interaction-design principles. No competitor flows have yet received hands-on evaluation.
- **Checked:** reviewed the current `Play.State`, `Play.Character`, `Panels.Field`, GM request context, and player play-page projection. No feature code or campaign data was changed in this planning pass.

## 2026-09-29 — In-progress implementation checkpoint

- Added atomic campaign setup for starting world details, GM-controlled characters, and typed campaign panels with public/private visibility.
- Added the session play screen with campaign-wide timeline, NPC speech and activity, world header, action composer, pending/retry states, and a player-click D20 flow.
- Added the local ChatGPT-plan OAuth and streamed Responses adapter behind fake-testable boundaries. No live account was connected in this checkpoint.
- **Checked:** focused campaign/panel checks passed for the new behavior, and the session plus campaign LiveView suite passed (11 tests, 0 failures). See `docs/CHECKPOINT_2026-09-29.md` for integration status and remaining work.

## 2026-09-29 — Campaign panel updates in the turn loop

- GM proposals can update existing typed panel fields using stable campaign keys. Unknown fields, invalid values, negative quantities/money, and unsupported formulas fail validation before any changes apply.
- Panel updates commit in the same database transaction as the turn and its audit events. Public fields appear in the play page and public timeline; GM-private panel changes stay out of player projections.
- **Checked:** the complete WSL suite passed (76 tests, 0 failures), warnings-as-errors compilation passed, and the additive panel migration ran against the persistent development database.

## 2026-09-29 — Localized interface and bounded campaign memory

- Added a persisted English/Spanish/French interface selector across the campaign library, setup, details, account connection, and session play screens. User-authored story content and the selected narration language remain campaign data.
- Added translated validation and error messages. Gettext extraction found 236 current UI strings; Spanish and French catalogs both merge with zero missing messages.
- Added separate persisted public and GM-private history summaries. Each is bounded to 6,000 characters, and each request includes at most the most recent 40 timeline events. Summary updates validate and commit with the turn; older timeline events remain in durable storage.
- **Checked:** `mix format`, `mix compile --warnings-as-errors`, and the full test suite (80 tests, 0 failures) passed. Locale behavior tests exercise translated campaign screens, content preservation, and the CSRF-protected locale selector post. Migrations 00400 and 00500 were applied additively. The local HTTP check returned 200 and displayed the fictional QA campaign. Visual/accessibility inspection and live OAuth remain outstanding.

## 2026-09-29 — Tabletop play-screen visual pass

- Shifted the campaign library and play screen toward a shared tabletop mood with a darker forest palette, warm brass accents, a framed scene area, parchment-toned narration, distinct dialogue bubbles, and a connected world-state rail.
- Kept the campaign library spacious around its single active campaign rather than leaving the card stranded on one side of the page.
- **Checked:** rebuilt assets and reviewed headless Edge screenshots of the library and fictional QA session at a 1440px capture width. Keyboard, narrow-screen, and screen-reader review are still outstanding.
- Reviewed the local connection screen and found the port-4000 process was started before `TokenStore` was added to the supervision tree; `/auth/connect` raises in that stale process. The existing server was left running, and the checkpoint now calls for a restart before account-flow review.

## 2026-09-29 — ChatGPT plan usage cues

- Added a connection-state cue at the play composer: connected players see that the turn uses their ChatGPT plan and can open usage settings; disconnected players can open account setup.
- Added the same usage-settings link to the connected account page and translated all new copy into Spanish and French.
- **Checked:** focused account and session LiveView tests passed (9 tests, 0 failures), the full suite passed (82 tests, 0 failures), and formatting, warnings-as-errors compilation, and asset build passed. A local request to `/auth/connect` returns HTTP 200 under the restarted WSL Phoenix server. The owner has not completed OAuth consent or a live model call.

## 2026-09-29 — Keyboard and reduced-motion affordances

- Added a high-contrast `:focus-visible` outline for interactive elements across the tabletop theme.
- Reduced animation and transition duration for visitors who prefer reduced motion, including pending-turn indicators.
- **Checked:** the frontend asset build passes. Real keyboard navigation, narrow-screen, and screen-reader review are still outstanding.

## 2026-09-29 — Streamed plan-error recovery

- Fixed handling of HTTP error bodies returned as Req `into: :self` asynchronous streams. The error parser consumes bounded response bodies before decoding their JSON error code.
- Added recovery mappings for ChatGPT plan usage, eligibility, and unsupported-route/capability errors so saved turns reach the intended retry guidance instead of a generic provider failure.
- **Checked:** adapter behavior tests passed (9 tests, 0 failures), including synthetic Req async-body messages for HTTP 429, 503, 403, and 400 cases. The full WSL suite passed (83 tests, 0 failures), as did formatting and warnings-as-errors compilation. No live account or model request was made.

## 2026-09-29 — Versioned GM policy

- Recorded the original vineyard chat's gameplay rules in `docs/GM_POLICY.md` without including its private plot or state: the GM advances time and weather, the player makes decisions and supplies rolls, and the in-world date remains visible.
- Updated the import plan to reflect read-only access to the original chat and the need to review truncated long messages before reconstructing campaign state.
- **Checked:** Compared the policy against the opening vineyard instructions and later explicit player corrections about time, date, and weather.

## 2026-09-29 — Campaign and session foundation

- Added a reviewed campaign setup with title, premise, setting, tone, narration language, and player character details.
- Added a persistent campaign list and detail page with session history, resume links, archive, and restore actions.
- Campaign creation saves the campaign and its first session together. Starting a later session closes the previous active session in the same transaction; a database index enforces one active session per campaign.
- Added a fictional QA campaign seed, separate campaign fixtures for tests, and WSL/PostgreSQL setup notes. No vineyard data is included in the QA seed or automated fixtures.
- Bound the LiveView server to `127.0.0.1:4000`, restricted development WebSocket origins to `127.0.0.1:4000` and `localhost:4000`, and disabled sensitive DB details in connection errors.
- **Checked:** `mix format` completed, the focused Campaign/LiveView suite passed (13 tests, 0 failures), and the complete suite passed (18 tests, 0 failures). Development migrations ran against `storyteller_dev`; automated tests used `storyteller_test`.

The resumed session page currently confirms stored campaign/session setup; the interactive turn screen is the next feature.

## 2026-09-29 — Persistent play and OAuth foundations

- Added campaign-scoped world and character records with separate public and GM-private facts, plus ordered turn events across multiple sessions.
- Added idempotent player actions, validated GM proposals, atomic state application, recoverable failures, and an explicit player-click D20 that records one result.
- Closing a session or archiving a campaign invalidates open turns. A generation counter prevents late GM responses from applying after retry or closure.
- Added local credential storage and OIDC validation primitives for the planned ChatGPT sign-in flow. No account was connected and no live model request was made in this slice.
- **Checked:** WSL formatting and warnings-as-errors compilation passed. The isolated `storyteller_test` database was recreated for the revised migration; the complete suite passed (44 tests, 0 failures). A separate read-only review found no remaining Play lifecycle or retry issue.
- An additive reconciliation migration installed the final lifecycle triggers and positive event-sequence constraint in the durable development database, which had applied an earlier draft of the Play migration. The existing campaign record remained present. The same migration also ran successfully against the test schema where those objects already existed.
