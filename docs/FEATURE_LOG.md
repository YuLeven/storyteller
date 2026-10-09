# Feature log

## 2026-10-08 — Exercise ensemble play and player-led task choice

- In a separate fictional QA campaign on GPT-6 Luna at low reasoning, two present companions handled different requested checks. They gave separately attributed findings without narration repeating their answers, and uncertain evidence remained uncertain.
- When invited to take the lead, they offered distinct role-fitting tasks. The player chose a routine task with one companion; the GM followed the established route, left the other companion behind, and resolved the task in one concise beat. The player board showed the matching location, elapsed time, and remaining presence. No blocker or roll was added.
- The investigation answer itself did not suggest a next lead; the player had to invite the GM to surface another task. Keep testing natural handoffs and more clearly differentiated voices. This is a focused positive sample, not evidence that the story-quality goal is complete.
- Recent stage logs showed first output around 1.9–5.1 seconds and streams around 8.6–11.5 seconds in a small uncorrelated batch. That batch also included one `location_presence` rejection and internal same-turn correction; current logs do not identify which player action it belonged to. Treat these as diagnostic observations, not a benchmark. Measure the full pending-action and reveal experience with turn-correlated timestamps.
- No runtime code changed in this iteration; no test suite was run. The separate QA play screen and final board state were checked directly.

## 2026-10-08 — Keep spoken lines attributed once

- An NPC-led Quiet Observatory turn let Inés choose the next task and carried Mara to the observing terrace; its two-minute travel and current place agreed. However, Inés's full quoted invitation appeared in both GM narration and her speech bubble. In a later comparison beat, narration and speech paraphrased the same finding. That makes the character sound mechanically repeated and dilutes the scene.
- Strengthened the runtime channel guidance so narration stages a finding without announcing it, and each spoken line remains in structured dialogue. Added a narrow pre-validation safeguard that removes an exact, long quoted duplicate from GM narration while keeping the NPC's attributed line.
- A subsequent Luna-low action asked Inés to read the two records side by side. The GM only staged the page and morning light; Inés delivered both recorded times (10:14 p.m. and 10:41 p.m.) and preserved uncertainty about which was right. The in-world clock did not advance. This is one positive case, not a guarantee across scenes. No cause was invented and no existing campaign events were rewritten.
- Added a fake-provider regression proving the exact quoted echo is removed from narration while the NPC's speech bubble and distinct scene action remain. The full Play suite initially exposed two provider-start waits relying on ExUnit's 100 ms default; those harness waits are now explicitly bounded at 1 second, and the rollover case passes alone.
- **Checks:** the complete Play suite passed (**163 tests, 0 failures**) in WSL against `storyteller_test`; the request-contract, exact-echo, and rollover regressions passed. Formatting, warnings-as-errors compilation, and `git diff --check` passed. No expensive-model comparison was run.

## 2026-10-08 — Keep narrative beats and NPC dialogue from echoing

- A focused Luna-low Quiet Observatory follow-up established a useful answer, but the GM narration and Inés's speech bubble repeated the same conclusion and caveat. That felt like one line delivered twice instead of a character contributing naturally to the scene.
- Clarified the runtime GM contract: when an NPC delivers a finding, the narration sets the moment without restating it; an echo remains welcome when it conveys a meaningful reaction or change in emphasis. Updated story acceptance criteria and added a request-contract regression. This is a prompt-direction fix; it does not prove that all generated dialogue will avoid repetition.
- One post-change Luna-low turn in the isolated Quiet Observatory campaign used a brief GM stage-setting line and let Inés deliver the finding and what remained uncertain. The adjacent narration did not repeat her answer, and the in-world date/time remained unchanged. This is one positive sample, not proof of reliable dialogue quality or broad latency.
- **Checks:** the focused GM request-contract regression passed (**1 selected, 0 failures**) in WSL against `storyteller_test`; formatting and `git diff --check` passed. No expensive-model comparison was run.

## 2026-10-08 — Reconcile GM-confirmed companion movement with player travel

- Quiet Observatory live QA exposed a state gap: the player asked Inés to walk from the north terrace to the record room, and the accepted scene showed them working there together. If a streamed proposal omits Inés's canonical location change, ordinary presence validation can force another generation attempt even though the accepted story makes her arrival clear.
- Added narrowly grounded reconciliation when the action names a co-located public NPC invitation, the player's move resolves to a known public destination, narration explicitly confirms that same NPC crosses into that same destination, and no roll is outstanding. Direct questions and tentative invitations let the GM decide whether the NPC accepts; a refusal or scene that leaves them behind does not move them. The inferred operation still goes through the normal route, duty, visibility, presence, and atomic commit validators.
- Fake-provider coverage verifies direct and tentative invitations when GM narration confirms travel, plus declined/unaccepted scenes, coherent final locations, and exactly one saved action/story reply. A focused WSL selection across the new regressions and existing movement, roll, route, and barrier cases passed (**19 selected, 0 failures**). This change did not make a live provider request; the live sample confirms story continuity but does not prove that the new inference path itself ran.
- **Checks:** focused movement selection passed (**19 selected, 0 failures**); the complete Play/SessionLive suite passed (**249 tests, 0 failures**) in WSL against `storyteller_test` with fake providers. Formatting, warnings-as-errors compilation, and `git diff --check` passed. No live provider request was used to test this implementation.

## 2026-10-08 — Make state-change repairs concrete after live movement QA

- Automatic recovery resumed the same Quiet Observatory action without another player submission. Earlier provider proposals failed `location_presence` and `world_change` validation; the saved action remained intact and invalid state never committed. Rejected model output is not retained, so the exact malformed fields cannot be diagnosed from those responses.
- Tightened the runtime GM policy and correction guidance to make each state channel explicit: `public_changes` for date/time/weather, `location_changes` for place/presence, `inventory_changes` for owned items, `panel_changes` for resources, and `private_changes` for GM-private world facts. Added a fake-provider regression that puts location in the wrong field and verifies the same turn succeeds after actionable repair.
- In a later focused Luna-low replay of that same saved action, the player reached the record room in two in-world minutes with Inés present. They compared the old notes; the narration preserved that no matching pulse or cause was established and left the clock untouched. The action and reply each appeared once. A follow-up question about the earliest dome entry completed in one provider stream: first output arrived in about three seconds and the turn committed in about thirteen; Inés answered directly, the note did not invent a cause, and game time did not advance. These are positive samples, not proof that first-response reliability or campaign-wide story quality is solved.
- Updated the canonical GM policy and player-facing QA acceptance contract. No campaign content is included in repository documentation.
- **Checks:** the `Play` and session `SessionLive` suites passed (**246 tests, 0 failures**) against `storyteller_test` with fake providers. `mix format --check-formatted`, warnings-as-errors development compilation, and `git diff --check` passed. The live sample used only the existing isolated Quiet Observatory campaign and GPT-6 Luna at low reasoning effort.

## 2026-10-08 — Recover the same action when the provider cannot confirm usage

- The Quiet Observatory QA session's saved movement/action could not be resolved because the ChatGPT-plan provider returned `usage_unavailable`. A single intentional Luna retry returned the same status; the saved action and campaign canon remained intact. The persisted default GM model for this isolated campaign is `gpt-6-luna`.
- Treat provider `usage_unavailable` as transient in Play and LiveView recovery. The existing same-turn recovery loop retries it in the background, retains the visible pending action, and resumes it after reconnect; an explicit usage limit, pause, credential issue, or local context correction remains a different state that must not be automatically resent.
- Added behavioral coverage for recovery after a temporary provider usage-status failure, verifying the story commits once with one player action and one GM reply. The live account remained unavailable during the single manual Luna retry, so no live recovery success or story-quality result is claimed from this attempt.
- **Checks:** both new focused regressions passed; the complete `Play` and session `SessionLive` suites passed (**245 tests, 0 failures**) in WSL against `storyteller_test` with fake providers. `mix format --check-formatted`, warnings-as-errors development compilation, and `git diff --check` passed. No live model call was made for verification after the recovery change.

## 2026-10-08 — Keep narrated travel moving while preserving meaningful rolls

- A routine walk to a uniquely identified NPC can no longer stall on a roll the GM itself calls routine after already narrating the arrival. Storyteller records the player's public-location move and drops only that redundant travel check. If the accepted response instead asks for a separate uncertainty (such as persuading the NPC), the move and canonical route time commit while the player still rolls for that uncertainty. A clearly risky movement test remains unresolved before crossing; no other state edits can piggyback on movement while that roll is pending.
- Behavioral regressions cover all three cases with deterministic providers: routine walk plus narrated arrival completes in one provider response; narrated arrival plus persuasion moves only the player and leaves the persuasion roll pending; risky ledge crossing leaves the player at the threshold with the crossing roll pending. The broader Play/WorldClock/SessionLive behavior suite passed after these changes (247 tests, 0 failures). No live provider calls were made.
- This supports the product priority in `AGENTS.md`: fun, engaging, quick-paced, consistent, lifelike play; cost is never the goal. The recent one-stream Luna movement check still had required internal correction on its first response; this fake-provider edge-case fix does not establish that the live mismatch is resolved.

## 2026-10-08 — Resolve a committed move to an off-scene public character

- A committed player action can target one uniquely identified GM character by name when the character's canonical current place is public. Storyteller fills only the missing player movement, leaves the NPC's location unchanged, and then runs the normal route, duty, visibility, roll, and presence checks. An explicitly named public place still takes precedence. Hypothetical questions, NPC-directed movement, private or unknown locations, ambiguity, real barriers, and unresolved rolls do not trigger the inferred move.
- Added a behavioral regression matching natural phrasing from play: “I walk over to Ines and ask if the comet is still visible.” With Ines at a known public place, the fake provider completes that action in a single request, commits the player's location, and leaves Ines where canon placed her. The broader relevant Play/WorldClock/SessionLive suite passed after the change (245 tests, 0 failures); the targeted exact-phrasing test passed (1 selected, 0 failures).
- In one separate Luna-low live check, Ada walked from the Lower dome toward Ines at the West observing platform. The final turn was coherent: Ada and Ines were together on the platform, Mara remained in the Lower dome, the question was answered, and the game clock advanced one minute. The first provider response nevertheless hit location_presence, so an internal same-turn correction was still needed. Provider stream stages were about 10.8 seconds and 6.4 seconds (first output around 3.8 and 1.6 seconds); these are not end-to-end latency measurements. The player did not re-enter the action, but this remains slower than the intended first-response flow. The rejected proposal is not retained, so its precise mismatch is unknown and needs safe, more specific diagnostics before we claim this is resolved in live play.
- No Vineyard campaign or source conversation was accessed. The live check used the separate fictional Quiet Observatory campaign on GPT-6 Luna at low reasoning effort.

## 2026-10-08 — Advance authored clocks and reconcile only clear missing movement

- The Quiet Observatory QA clock was recorded as `04:44, minutes before dawn`. Six canonical elapsed minutes appeared only as a secondary cue, leaving the main Time panel stale. The clock parser now advances a valid numeric prefix before a comma and preserves the descriptive suffix; free-form labels and invalid prefixes remain untouched. The LiveView regression uses this exact shape, and unit cases cover the observed 24-hour label, a 12-hour midnight rollover, and non-parseable wording.
- On the live fictional scene, the GM resolved a six-minute watch in one GPT-6 Luna low-reasoning stream: the bell stayed still, Mara gave a concise in-character observation, and the board moved from 04:50 to 04:56. The action is stamped at 04:50 and the response at 04:56; no extra player prompt or retry was needed. One response is evidence for this time-passage task, not broad story-quality or latency proof.
- A follow-up live return from the west platform into the lower dome narrated Ada arriving and answered her question to Mara, but the first proposal still failed `location_presence`; the internal correction committed the same saved action in a second stream. This shows the movement issue is not fully solved in live play. The rejected proposal is not retained for diagnosis, so the broad failure category does not identify which presence field caused it.
- Deterministic movement reconciliation now catches a committed same-clause move to one established public destination when the accepted narration confirms the player's arrival, even if the proposal contains other valid changes but omits the player's move. It appends only the player's move and lets the normal validators enforce routes, duties, visibility, rolls, and presence. A question, uncommitted intention, unresolved roll, explicit player-blocking obstacle, or a shut door behind an arrival does not synthesize movement. Fake-provider cases cover those edges and a proposed companion move; the connected return still needs follow-up diagnosis.
- **Verification:** 241 relevant Play/WorldClock/SessionLive tests first passed together; after the partial-change guard was broadened, nine focused movement, clock, and LiveView regressions passed (**0 failures**). Warnings-as-errors development compilation and format checks passed in WSL against the isolated test database. The live time-passage turn completed in one provider stream (about 6.4 seconds, first output in about 2.1); movement out completed in one stream (about 5.6 seconds, first output in about 1.5); the return required a first stream of about 6.6 seconds and correction stream of about 6.9 seconds (first output about 2.0 and 1.5 seconds). These are overlapping provider-stage observations, not end-to-end latency benchmarks. No Vineyard campaign or source conversation was used.

## 2026-10-08 — Commit ordinary player movement even when narration jumps ahead

- In the isolated `Quiet Observatory QA — The Last Bell` campaign, Ada explicitly stepped through an open doorway into the lower dome and asked to inspect the bell. The first GM proposal answered from beside the bell but omitted the canonical movement operation. Storyteller rejected that proposal before committing it, then automatically corrected the same saved action; the accepted narration described the close-up observation and the board moved Ada to the Lower dome with Mara present.
- The pending-action treatment kept the exact player action visible while correction was underway. The player did not have to resubmit or reconstruct their action, and no stale platform location was left beside the accepted scene.
- This turn needed one internal correction: the first provider stream took about 10.0 seconds, and the corrected stream about 10.6 seconds. The additional first-output indicator appeared about 3.8 seconds into the correction stream. This is a single live sample, not a latency benchmark; the extra round trip is still slower than a clean first proposal and should become less common through clearer primary movement guidance.
- Added proactive GM guidance that a committed crossing must update `location_changes` even when the narration jumps directly to destination observations. In one follow-up live action, Ada stepped back through the same open door onto the west platform and looked up at the comet. The GM immediately narrated the new view, the world board returned to the west platform, Ines was present and Mara was correctly elsewhere, and the clock advanced one minute. It completed without a correction: first output arrived in about 1.5 seconds and the provider stream finished in about 5.3 seconds.
- **Verification:** the Play and context-budget suites passed (**188 tests, 0 failures**); development compilation with warnings as errors, formatting, and `git diff --check` passed. The pending-action LiveView regression passed (**1 selected, 0 failures**). The live return is one positive first-response sample, not a latency or broad story-quality benchmark. The same-turn regression models the original failure: committed crossing with close-up result prose but no repeated entry language must be corrected before state commits. The correction prompt requires a matching canonical move when no established barrier or unresolved roll stops ordinary travel, while questions, intentions, and actual narrated barriers remain non-movement cases.

## 2026-10-08 — Movement correction still recurs on a conversational entry

- In the same fictional QA scene, Ada returned through the open door into the Lower dome and asked Mara whether she recognized the bell's fresh scratches. The first proposal narrated Ada entering and gave a natural, cautious Mara answer, but validation rejected it at `location_presence`; same-turn correction then committed the response and the board showed Ada and Mara together in the dome. The player action stayed visible throughout.
- This turn used two provider streams (about 7.6 and 9.5 seconds); first output arrived after about 4.1 seconds initially and 3.2 seconds on correction. The dialogue itself was a useful handoff, but the extra request made the exchange feel slow. Along with the earlier corrected inspection and one clean return, the samples show movement guidance is not yet reliable enough to avoid correction calls. Continue examining a safe application-side reconciliation for an unambiguous player-committed move, preserving actual barriers, unresolved rolls, duties, route checks, and player agency.
- No further live request was made for this finding. It was a focused follow-up in the separate Quiet Observatory campaign using GPT-6 Luna at low reasoning, not a measured failure-rate benchmark.

## 2026-10-08 — Let routine movement proceed and keep narrated arrivals canonical

- In a newly authored fictional campaign, `Quiet Observatory QA — The Last Bell`, the GM opened with an atmospheric storm easing around an observatory telescope, a newly visible comet, and a bell ringing from the sealed lower dome. Ines and Mara were introduced through their work and distinct lines, leaving the player a clear opening. Ada then crossed the wet platform to ask Mara about the sealed door; the GM let that ordinary movement and conversation proceed without inventing a route barrier or demanding a roll.
- A later player action asked Mara to unlock the lower dome and followed her inside. The GM described Ada and Mara entering, then gave Mara a useful warning about the swollen sill. However, it omitted `location_changes`: the canonical board still placed Ada, Mara, and Ines on the west platform. This was a real story/state drift, not a UI projection bug. One live sample used the connected GPT-6 Luna route at low reasoning effort. The opening provider stream took about 8.7 seconds, and the routine move/conversation stream about 17.1 seconds; these are provider-stage measures (including an automatic JSON correction on the latter), not submit-to-render latency or a benchmark.
- Added narrow consistency checks: when the saved player action explicitly describes crossing a spatial boundary and public GM output confirms the player's crossing, a missing player move becomes a `location_presence` proposal rejection. The same check catches named GM characters the accepted scene directly has crossing a boundary without movement operations. A question, future intention, or name mention alone does not move anyone. The existing internal correction path repairs the same saved turn before committing anything; the GM supplies the place and actual movers, and normal route, duty, visibility, and presence validators still decide whether the movement is valid.
- Fake-provider behavior tests exercise both cases at `Play.submit_turn`: a contradictory player-entry response is discarded, then one correction creates a place and route, moves the player and accompanying Mara, keeps Ines behind, and commits once; an NPC-only entry is repaired by moving Mara while Ada remains at the telescope. Existing ordinary-room movement and arrival/duty safeguards were rerun. The initial validator work was committed before further live testing; the connected correction result is recorded in the follow-up entry above.
- **Verification:** full `Play` tests passed (145 tests, 0 failures), and the full context-budget suite passed (43 tests, 0 failures). The development compile passed with warnings treated as errors; formatter and `git diff --check` passed. Targeted regressions cover ordinary movement, new-room correction, NPC-only movement, named-arrival reconciliation, active-duty protection, and long relevant voice guidance. The fixture was corrected to reflect trailing-space normalization at character save time. A free-form clock label in this QA sample remained unchanged while elapsed minutes advanced; review whether that is clear enough for players without guessing or rewriting their authored date/time.

## 2026-10-08 — Let a look-around answer use all relevant scene evidence

- The direct look-around prompt capped a follow-up at one new detail, which could leave useful parts of the scene undescribed. Replaced that arbitrary output cap with relevance guidance: provide salient supported details for the question, avoid repeating known facts, and do not turn an observation into an exhaustive inventory. This is about a richer, more useful scene, not minimizing cost or response size.
- Also softened the shared sparse-scene guidance: one or two ambient details may suffice, but add more when the scene or player's action calls for them. Keep texture relevant and non-actionable instead of padding. A behavioral regression covers the revised policy; this particular global guidance has not yet been checked in a live sparse opening.
- A fake-provider behavioral regression now asks about the dome and preserves several GM-authored sensory details while verifying a question turn does not change canon or world time. In one live follow-up in `Quiet Observatory QA — The Nine-Minute Window`, the GM described the steady telescope and its regular tick, caught shutter and taut cord, the brightening clouded opening, the marked chart and comparison, and the uncertainty around the offset's cause. It gave practical conditions for Nadia's next choice without appending a generic question. Reload preserved the question and answer, while date/time, weather, location, scene, and character presence remained stable.
- The first provider response failed JSON decoding; the same saved turn recovered through the internal correction and completed without player intervention. Settings confirmed GPT-6 Luna; the request uses low reasoning effort. The first stream took 6.892 seconds, the corrective stream 6.333 seconds (about 13.2 seconds combined provider streaming); first output arrived at 4.280 seconds initially and 2.250 seconds on correction. These are overlapping stage measures from one turn, not submit-to-render latency or a benchmark.
- **Verification:** the focused fake-provider test passed; formatting, development compilation with warnings as errors, and `git diff --check` passed in WSL. This sample verifies one multi-detail answer and an automatic decode recovery, not broad narrative quality or repeatability.

## 2026-10-08 — Let direct character dialogue complete the player's question

- In `Quiet Observatory QA — The Nine-Minute Window`, Nadia kept the mount braced and asked Sera what the comparison established and what it did not. Sera answered in character: she named the observed lateral offset, qualified the earlier readings as blurred but non-contradictory, and clearly separated the observation from its unknown cause. The GM briefly narrated Sera turning from the eyepiece to her chart, then yielded naturally without a stock follow-up question.
- This was one saved turn: the player did not need to repeat the question or action; the mount remained braced and the in-world clock, weather, location, and presence stayed unchanged. Reload preserved the exchange. Settings confirmed GPT-6 Luna at low reasoning effort. Provider first output arrived at 4.233 seconds and the provider stream completed in 9.719 seconds; these overlapping measures are not submit-to-render latency or a benchmark.
- **Evidence:** one positive connected dialogue sample for voice, evidence-versus-interpretation, player agency, and natural handoff. It does not prove consistency across characters, languages, or scenes; repeated human review and latency-tail measurements remain open.

## 2026-10-08 — Carry the player's stated support through a delegated beat

- In the fictional `Quiet Observatory QA — The Nine-Minute Window` scene, Nadia braced the telescope mount and delegated the comparison to Sera. The GM let the Moon enter the field and had Sera announce she was beginning the comparison, but stopped before the bounded comparison result. Nadia then had to spend another prompt explicitly keeping the mount steady while Sera finished. That was unnecessary friction: the supporting action and delegation were already clear, and no new consequential choice had appeared.
- The compact GM policy now says that an explicitly committed, bounded supporting action carries through the delegated task's result in the same response unless a real interruption or consequential choice arises. It still forbids inventing player acts, NPC success, or outcomes unsupported by canon. A fake-provider behavioral regression checks the stated follow-through appears in the accepted narration and the delegated result completes without a forced question.
- **Live check:** in one follow-up action in the same isolated campaign, Nadia kept the mount braced while Sera compared the observation with the earlier readings. The GM narrated the support, completed the comparison in that response, gave Sera's qualified result, and let Tomas add one concise reaction. Nadia did not need another prompt to make the task finish, and the response did not end in a forced question. Reload preserved the player action, narration, dialogue, scene, and character presence. Settings showed GPT-6 Luna; the request envelope supplies low reasoning effort for Luna. Staged telemetry recorded 3.743 seconds to first output and 8.231 seconds for the provider stream; context load/build took 163 ms total and validation/commit 36 ms. These are observations from one turn, not a latency benchmark or broad quality claim.
- **Verification:** the focused regression and complete Play test module passed (**142 tests, 0 failures**); WSL formatting, development compilation with warnings as errors, and `git diff --check` passed. The earlier isolated scene also correctly paused for Nadia's D20, accepted her player-controlled 17, and persisted the result after reload. Matched testing across scene types and repeatability remain open.

## 2026-10-08 — Resolve a routine evening at montage scale

- In the isolated fictional Quiet Observatory QA campaign, Mara chose to review her own field notes, sleep, and continue in the morning. The GM compressed the evening and night into a coherent scene beat, kept the lantern room and Ilie present, and advanced the in-world date/time to 25 October 1891, Morning.
- The narration described the wind easing and rain thinning to drizzle; the weather panel changed to the same public condition. Ilie's brief line returned control without an obligatory question. Reload preserved the new time, weather, location, presence, and story. This is one positive routine-work sample, not proof for high-stakes or ensemble pacing.
- Staged telemetry showed roughly 4.0 seconds to first output and 9.1 seconds for the full stream (overlapping measures); validation and commit were brief. GPT-6 Luna at low reasoning effort was used for this isolated scene.

## 2026-10-08 — Keep a short character exchange alive without filler

- Continued the newly created fictional Quiet Observatory QA campaign in the isolated QA database using GPT-6 Luna at low reasoning. After the tasting beat, Mara asked Ilie whether autumn weather often kept the observatory indoors. Ilie answered in one concise, dry metaphor; a brief GM line refreshed the rain and steam without changing the weather or adding a forced question.
- This was one dialogue-scale sample: about 3.9 seconds to first output and 6.9 seconds for the provider stream (the measures overlap). It supports a natural, brisk short exchange in this scene; it does not establish ensemble, high-tension, long-scene, or latency-distribution quality.

## 2026-10-08 — Let the GM establish tasting facts first

- Ran one focused live play check in a new fictional campaign, `Quiet Observatory QA — Lantern Room Tasting`, in the isolated `storyteller_quiet_observatory_20261007_codex1` database. The connected model was GPT-6 Luna at low reasoning effort. No other campaign data was used.
- The opening grounded the lantern room in rain and ridge wind, described the infusion's mint aroma and pear scent, and introduced the present caretaker with a brief characterful line. After the player poured a cup and sipped, the GM supplied observable color, aroma, sweetness, cooling mint, and pear finish before ending with the caretaker's small gesture. It did not ask the player to invent a taste or dictate the botanist's judgment.
- The turn used one player action and returned one cohesive GM response. Staged telemetry measured about 7.2 seconds for the opening and 5.7 seconds for the tasting turn, including streaming, validation, and commit. This is one deliberately narrow sample; it does not certify overall latency, adaptive pacing, or campaign-wide story quality.

## 2026-10-08 — Repair safely rejected GM proposals on the saved turn

- A strict validator could reject a response even when the saved player action and current canon gave the GM enough information to correct it. Requiring the player to click Retry for each safely repairable schema/canon mistake made ordinary play feel brittle.
- The same claimed turn now gives the GM category-specific correction guidance for up to four proposals after the original. Validation stays strict: only a complete accepted proposal can append story events or change canon, and the saved action and any D20 result are reused. If the same category returns an identical rejected response, a stronger correction tells the GM to change it; recovery stops only if that identical response repeats again. A changed response may still make progress. Account, usage, provider-context, and other intervention paths keep their distinct handling. This retry bound guards against identical non-progress; it is not a model-spend or prompt-size objective.
- Behavioral tests cover progressive player-agency/dialogue/time corrections committing the action and narration once, changed responses within one category, recovery after one identical repeat, no partial events after a second identical repeat, and an existing travel-duty safeguard.
- **Verification:** four focused recovery/travel tests passed; the full isolated WSL suite passed (**565 tests, 0 failures**, `--max-cases 16`); development compilation with warnings as errors, formatting, and `git diff --check` passed. Tests used fake providers and `storyteller_test`; no live model request, OAuth consent, or campaign data was used.

## 2026-10-08 — Smooth streamed narration previews

- Streaming the GM's JSON proposal used to reparse its growing prefix and send a LiveView update for every provider text delta. Providers may split even a few words into many tiny events, adding avoidable local work and message traffic while the player waits.
- The adapter now scans and forwards provisional narration after meaningful source growth, while the separate first-output status remains immediate. A completed stream flushes any newer final narration; previews remain restricted to the top-level narration field and keep their existing size bounds. Failure and turn-completion cleanup remain unchanged.
- A deterministic fake-stream regression splits a long narration into hundreds of tiny deltas and verifies bounded preview updates and a complete final draft. Existing tests continue to check that dialogue/private proposal fields never enter the preview and that failures clear it.
- **Verification:** focused OpenAI adapter tests passed (**38 tests, 0 failures**); targeted LiveView preview and failure-cleanup checks passed (**2 selected, 0 failures**); the complete isolated WSL suite passed (**561 tests, 0 failures**, `--max-cases 16`). Development compilation with warnings as errors, formatting, and `git diff --check` passed. No live model request, OAuth consent, campaign data, or non-test database was used.

## 2026-10-08 — Let ordinary actions proceed on incomplete maps

- Product feedback identified a frustrating refusal pattern: the GM treated an unrecorded walking route or unknown NPC availability as an obstacle, then narrated irrelevant exact stock totals. The game should follow clear player intent unless canon establishes a real barrier.
- The owner clarified that context should be smart and relevant, not kept small for cost's sake. Removed arbitrary per-instruction size assertions; normal gameplay requests do not attach an exact serialized-body ceiling. The adapter's optional exact-size check remains for explicitly configured uses outside normal play, while prompt sizing uses a compaction target rather than per-section quotas.
- **Priority clarification and context follow-up:** the campaign's success order is fun, engagement, quick pace, consistency, and lifelike characters; cost is not a target. Relevance scoring now matches whole words, so “ask” no longer pulls every unrelated “task” record through substring overlap. Character and place names are treated as explicit references only when the action names them; co-present characters, the current place, adjacent routes, and truly matching facts remain anchored. Inventory keeps every identity and quantity; it keeps every description/property when the whole request fits and compacts unrelated verbose detail only after the soft target is exceeded. A specifically named item keeps its full detail, while a broad inventory question keeps its details even if the best request remains above target. Under pressure, compact other unrelated fields while preserving matched scene facts, voices, resources, places, and memories; send the best relevant packet above target. Deterministic regressions cover the ask/task false match, a 20 KB target that still returns a much larger relevant packet with complete named-place, character, and objective details, broad and named inventory requests, and unrelated references being shortened first. Request-byte metrics remain diagnostics, never an optimization goal.
- **Verification for this pass:** full isolated WSL suite **560 tests, 0 failures** (`--max-cases 16`); dev compilation with warnings as errors, formatting, and `git diff --check` passed. Tests use the fake provider and isolated test database; no live request, OAuth consent, or campaign data was used.
- The GM contract and validator now treat a missing route edge between already established public places as incomplete map data, not a barrier. The player can move in the same turn; a co-present companion can follow only that same planned leg from their shared origin. The GM's proposed total turn duration is the only time input for an unrecorded trip, and the validator persists neither a made-up route nor an exact travel duration. Existing public routes still supply canonical duration; active duties, new-destination route requirements, destination visibility, and public-scene presence remain validated. Private route durations do not complete public trips or leak into public events, and off-scene NPCs still need their own established route before moving. Unknown NPC location is a reason to make sensible search progress, not proof of absence. Travel-intent detection tokenizes normalized English, Spanish, and French verbs so accented requests such as “Acompáñame” receive the structured route guidance; unrelated actions do not pay that prompt cost.
- Narration leaves unchanged stock and resource totals on their board panels. Mention a balance only when asked, materially changed, or useful to the immediate decision; narrate the outcome of the touched item without repeating unrelated ledger values.
- Clarified the GM's adaptive pace contract: routine actions should reach their immediate consequence and useful present-NPC reactions before returning control at a genuine decision; active intimate exchanges and already-established high-stakes moments stay line-by-line. Reactions must advance the scene instead of filling a roster, and the GM must not invent drama or the player's next act. A fake-provider request-boundary regression verifies this instruction is present on action turns; it does not claim the generated story follows it.
- Prompt sizing follows the owner's clarification that Storyteller is not optimizing for cost. Raised the default local compaction target from 64 KB to a generous 128 KB so ordinary rich scenes keep more useful canon; the target is not a model limit or cost objective: rank canon for the action, compact older/redundant history progressively, and shorten reference prose where useful; if the best relevant packet remains over target, send it. Gameplay requests carry no exact local body veto: the provider reports its actual model-context limit. Do not erase all history or flatten canon merely to satisfy an application byte count. A provider context rejection automatically rebuilds one scene-focused retry in the same claimed turn from the same saved player action. That recovery retains the concise core GM policy and built-in canon lookup, but drops optional MCP companion discovery, instructions, and tools for that retry so its space is spent on relevant scene facts. It preserves canonical source data and does not ask the player to shorten campaign notes. Deterministic regressions cover an over-target request reaching the provider, default-budget dense canon preserving its long relevant location detail, and provider context-window rejection recovering without a player-click retry.
- Follow-up correction to that policy: manual recovery no longer applies the older 48 KB target or the special four-event history squeeze. Its relevance-ranked campaign packet keeps useful canon under the ordinary generous compaction target, uses progressive relevance compaction only when needed, and omits optional MCP companions while keeping the full core GM policy. A distinct minimal scene packet remains available after another provider rejection. This is not a cost optimization; request-size measurements remain diagnostics and the selected provider decides whether its context window can accept the request.
- When an NPC's public location is unknown, a player explicitly seeking them is an active goal rather than evidence the NPC is absent. The GM should use a grounded routine/lead to make plausible search progress, while movement and dialogue validators continue to require accepted presence before claiming the NPC arrived or spoke. A fake-provider integration test verifies the player can move on an unrecorded ordinary route during the search, the GM has no permission to teleport or voice the unplaced NPC, and missing tracking data cannot strand the turn.
- Added deterministic Quiet Observatory regressions where the player goes to an off-scene NPC over an unrecorded route, transfers a bottle, advances only the GM-proposed turn time, and leaves the route graph unchanged; a return with zero proposed time also commits instead of failing for lack of map data. The test confirms a GM-private five-minute route cannot supply the public movement duration or appear in public events. Graph behavior tests cover a co-present companion moving before the player's same unrecorded leg, an off-scene NPC being unable to piggyback, and active-duty blocks. Existing regressions continue to cover known forty-minute travel, newly created destinations that require route operations, and off-scene dialogue without arrival. The movement-repair case verifies the route requirements for newly created destinations and companion/NPC guidance. Prompt assertions verify measurable request bytes are recorded, gameplay requests carry no local body ceiling, and movement-specific guidance is omitted for non-travel actions.
- One authorized Luna-low play check in fictional Quiet Observatory exposed a remaining schema-recovery gap: the draft narrated the requested walk, but movement validation rejected it, and the generic correction prompt did not repair the structured route in three provider calls. The action remains saved in that isolated QA session. A single retry after adding travel-specific instructions was blocked by the plan relay's HTTP 503 `subscription_sharing_user_unavailable`; a read-only audit still shows the latest QA turn failed with `usage_unavailable`. So the live play-quality acceptance remains open; no new live model request was sent during this patch. These are focused samples, not a quality or latency benchmark.
- **Verification:** the full isolated WSL suite passed (**554 tests, 0 failures**, `--max-cases 16`), including the over-target prompt, provider context-retry, long-history retention, TravelGraph, ordinary-travel, and new-destination repair regressions. Development compilation with warnings as errors, formatting, and `git diff --check` passed. Live play-quality acceptance remains open because the prior authorized Luna-low retry was blocked by the relay 503 above. No live model request or OAuth consent was performed for this patch.

## 2026-10-08 — Reconcile a clearly narrated player arrival

- A model can narrate the player's arrival at an established place but omit the matching structured move. Rejecting the whole turn in that case leaves the player stuck despite the accepted scene already saying they arrived.
- In the narrow case where the player action names one existing public destination with affirmative travel intent, the GM confirms the player's arrival there, and the proposal omits all location, route, and character-creation operations, Storyteller now supplies only the player's movement operation. The operation still goes through canonical place, route, duty, presence, and elapsed-time validation. It does not invent a route, place, NPC movement, or arrival; ambiguous destinations, an unconfirmed place mention, unknown places, and negated movement leave position unchanged.
- Fake-provider behavioral tests cover a multiword public destination, English, Spanish, and French arrival language for a single-word destination, no fabricated route, a binding NPC duty, and cases where the wording is insufficient to infer movement. This is a schema-recovery fallback, not general language understanding; cue coverage remains deliberately explicit and can be broadened from observed failures.
- **Verification:** targeted new arrival tests and the complete Play behavior module passed after fixing the tokenizer. Full-suite and release checks are pending. No live provider request or campaign data was used.

## 2026-10-07 — Keep requested tracked progress in sync with the story

- Live QA in the dedicated fictional Quiet Observatory campaign exposed a resource-canon gap: a three-day cataloging montage narrated that the public count rose from zero while the saved panel remained at zero. A retry then committed another vague “catalog advances” claim with no count change. The first run had failed proposal validation for a panel change; the second did not link the qualitative claim to a tracked update. This was safe from state drift only in the ledger—the story had already become inconsistent.
- Compact GM guidance now states the typed quantity/money delta and text/status/date set rules, requires narration to agree with the resulting value, and tells the GM to avoid claiming a count increased when no change is recorded. If a panel proposal is rejected, the automatic correction gives specific key, type, reason, update, and prose guidance.
- Added a deterministic guard for explicit player requests to track a visible resource: when the action contains both a write/record cue and a meaningful term from a public panel label/key, the proposal must include an operation for that field. Read-only inspection does not force a state change. A behavioral regression makes an omitted catalog update recover in the same turn, then verifies the public panel and event receipt contain the same +4 result; a separate inspection test confirms the cash balance remains unchanged.
- **Live QA:** On GPT-6 Luna at low reasoning, an explicit two-day catalog request first omitted the required panel operation and was rejected before canon committed. The automatic correction attempt then hit `unsupported_capability`; the saved action remained retryable. The same-turn UI retry again needed a validation correction, which returned a +6 quantity delta. The accepted narration said the catalogued total was 6, the board and event receipt showed 6, and the game clock advanced exactly two days; the unresolved clock mystery stayed unresolved. Reload confirmed the story and board persisted. This took a player retry after a separate provider error, so recovery still has friction. Four provider calls were used across the failed initial claim and eventual recovery; no Sol/Astra calls or Vineyard data were used. This is one focused QA sequence, not a general reliability or pacing benchmark.
- **Verification:** targeted Play tests passed (**2 tests, 0 failures**); prompt-budget regressions for time passage and observation passed after keeping the guidance compact. The full suite passed (**539 tests, 0 failures**) with `--max-cases 16`. A prior default-parallel run had one LiveView/DB ownership failure; that D20 test passed alone, and the reduced-parallel full run was clean. `MIX_ENV=dev mix compile --warnings-as-errors`, `MIX_ENV=test mix format --check-formatted`, and `git diff --check` passed.

## 2026-10-07 — Show safe provisional narration while the GM streams

- The session now displays a bounded preview from only the top-level `narration` string as streamed structured output arrives. It is labeled “Game master · live draft” and “May change”; raw output outside the safely decoded narration string, dialogue, state changes, and other payload fields are never shown in the preview. The preview is transient UI only and never enters the canonical timeline or campaign state.
- A new generation clears stale preview text. Provider errors discard the draft while leaving the saved player action visible. After successful validation/commit, LiveView removes the draft and shows the persisted narration once in the normal timeline. This improves perceived wait; it does not reduce model inference time or establish a latency benchmark.
- Player-action timeline timestamps now use the same projected elapsed world clock used to assemble GM context, so a legacy/stale display label does not stamp the submitted move with old in-world time.
- **Verification:** targeted stream-parser, provider-failure, LiveView reconciliation, and elapsed-clock regressions passed (**5 selected tests, 0 failures**). The full WSL suite passed (**538 tests, 0 failures**) with reduced parallelism; `MIX_ENV=dev mix compile --warnings-as-errors`, `MIX_ENV=test mix format --check-formatted`, and `git diff --check` passed. One owner-authorized live check on GPT-6 Luna at low reasoning, in the dedicated fictional Quiet Observatory QA database, showed the provisional draft while the turn was still in progress and then replaced it with the persisted narration and NPC reply after commit. This verifies the path once; it is not a latency or story-quality benchmark. No Vineyard data was accessed.

## 2026-10-07 — Recover campaign lookup calls from streamed Responses items

- The first live Quiet Observatory Luna retry exposed two gaps in the same turn. The API rejected a request carrying `text.format`; after removing that field, a tool-enabled stream could complete with an empty `response.completed.response.output` even though the model had emitted its function call in `response.output_item.done`. The adapter previously discarded that streamed item and reported an empty GM response.
- The adapter now retains completed streamed `message`, `reasoning`, and `function_call` items and uses them when the terminal output array is absent or empty. This preserves the full output for the existing local lookup validation and continuation path. The request continues to use the documented Responses fields without JSON mode; proposal shape is enforced by local validation and repair guidance.
- A regression test reproduces the empty terminal-output shape, verifies the local lookup runs once, replays the function call and reasoning into the continuation, and confirms the turn finishes with the follow-up narration.
- **Live QA:** the saved fictional Quiet Observatory action completed through the UI on `gpt-6-luna` at low reasoning. The GM answered the player's question with a coastal survey method and a distinct astronomy comparison from Mira, and the turn committed normally. Provider stage took about 17 seconds; first text arrived after about 4 seconds. This is one verified turn, not a latency or quality benchmark.
- **Verification:** WSL OpenAI adapter suite passed (**33 tests, 0 failures**); `mix format --check-formatted` and `MIX_ENV=dev mix compile --warnings-as-errors` passed. The first full-suite run had a one-off redirect in `campaign editor rejects stale voice edits from another tab and preserves them for review`; subsequent focused repetitions (10 runs), the full editor module, and a complete suite rerun all passed (534 tests, 0 failures). No campaign-editor change was needed. The live call used the owner's existing ChatGPT-plan OAuth session, Luna only, and the isolated Quiet Observatory QA campaign; no Vineyard data was accessed.

## 2026-10-07 — Recheck the ChatGPT-plan request contract for the input rejection

- Rechecked the current official SIWC preview and recovery documentation against the saved Quiet Observatory request. Storyteller uses the documented public `POST /v1/responses` route, `store: false`, `stream: true`, array input, and simple `{role: "user", content: "..."}` text item. The failed 14,398-byte request contained that single ordinary user item and no `additional_tools` lookup item.
- The docs say an HTTP 400 `subscription_sharing_unsupported_capability` requires inspecting both its code and `error.param`; this response exposed only `param=input`, without an error code, message, or request ID. `reasoning.effort` and `text.format` are not on the current unsupported-field list, but the SIWC guide does not explicitly demonstrate either field. There is not enough evidence to remove a field automatically or label this a known context-limit error.
- No live request or code change was made. Keep the saved action and manual same-turn recovery available while the cause is unresolved; do not make another identical probe. Official references: [SIWC preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations), [SIWC errors and recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery), and [SIWC models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).

## 2026-10-07 — Improve safe diagnosis of rejected GM requests

- Non-200 Responses diagnostics now include only allowlisted provider error types, a coarse message category, and numeric body/input/instruction byte counts plus input item count/kinds. Raw provider messages, prompts, campaign context, and input text remain out of logs.
- A fake HTTP regression verifies a missing-code `param=input` rejection is classified as input validation without exposing its message or the GM/player text. This prepares a safer next diagnosis; it does not resolve the current Quiet Observatory 400.
- **Verification:** WSL OpenAI adapter suite passed (**32 tests, 0 failures**) and the adjacent Play, OpenAI adapter, and context-budget suites passed (**201 tests, 0 failures**) with fake providers; formatting and `git diff --check` passed. No live provider call was made for this change.

## 2026-10-07 — Simplify the ChatGPT-plan user input item

- Rebuilt the saved Quiet Observatory request locally with a deterministic fake provider: the exact serialized request was 14,398 bytes against a 64,000-byte local guard, and contained one ordinary user message. The failure was not caused by Storyteller's byte preflight.
- Normal GM context now uses the Responses guide's simple `{role: "user", content: "..."}` text form instead of a typed `input_text` block. Request-budget estimation and behavioral fixtures use the same representation. A single Luna-low retry of the same isolated QA opening still returned HTTP 400 with `param=input`; the diagnostic had no error code, message, or request ID. This rules out the local byte guard as cause but does not identify the route rejection.
- The recovery policy is not limited to one total retry: transient failures continue automatic same-turn cooldown recovery. Repeating an identical rejected 400 did not help, so no further live requests were made. The original action remains saved, and the UI still offers a manual retry; removing that burden safely requires identifying the invalid field or adding a concrete compatible fallback.
- **Verification:** focused WSL Play, OpenAI adapter, and context-budget suites passed (**201 tests, 0 failures**) with deterministic fake providers; `MIX_ENV=test mix format --check-formatted` and `git diff --check` passed. Live QA used only `gpt-6-luna` at low effort against the fictional Quiet Observatory campaign.

## 2026-10-07 — Avoid repeating definitive provider failures

- An isolated Luna opening-scene probe was rejected by the ChatGPT-plan Responses route with HTTP 400 and `param=input`. The app then sent another provider request with correction guidance, despite having no model output to correct. Generic `provider_error` failures no longer trigger a hidden duplicate request; known transient classes keep their existing automatic recovery. The player's saved turn remains available for an intentional retry.
- The sanitized route diagnostic did not include a provider error code or message. Current docs support the input-item form and available fields, but the cause remains undetermined; inspect exact serialized size and request construction locally before considering another live probe. No further live requests were made during this investigation.
- **Verification:** WSL Play and OpenAI adapter suites passed (**161 tests, 0 failures**) using fake providers; `MIX_ENV=test mix format --check-formatted` and `git diff --check` passed.

## 2026-10-07 — Ask the GM for valid JSON

- Every Responses request now enables JSON mode for the GM's proposal. This prevents non-JSON syntax errors from consuming correction turns; Storyteller still performs the full schema, agency, visibility, and canon validation, since JSON mode does not guarantee any of those rules.
- The request-envelope estimate includes the format field. Fake-HTTP tests verify it is present on both the initial request and the bounded canon-lookup continuation. The SIWC preview's unsupported-field list does not include `text.format`, but this exact field has not yet been exercised on the connected ChatGPT-plan route; treat route acceptance as a live QA check, not as proven by these tests.
- **Verification:** focused WSL OpenAI adapter and request-budget checks passed with fake HTTP/provider responses; no live model request, OAuth consent, or campaign data was used.

## 2026-10-07 — Reduce transient retry bursts without asking players to retry

- A provider claim now gets at most one quick retry for provider-stage failures. Safe transient failures then keep resolving the same saved turn through the existing exponential cooldown; after four claims, each cooldown permits one half-open probe. The turn keeps its original action and commits its result once. This avoids five rapid requests against a continued network outage or rate limit while preserving automatic recovery.
- Fake-provider regressions verify a provider-unavailable outage makes at most two calls per early claim, crosses multiple cooldown cycles, and completes without a manual retry. Existing long-outage coverage now verifies recovery beyond four claims with one probe per cooldown. LiveView tests verify the action remains visible during this automatic recovery. Account/authorization, usage-limit, and context-size errors remain explicit intervention paths.
- **Verification:** focused WSL recovery selection passed (**212 discovered, 6 selected, 0 failures**); account-usage, authentication, and context-size intervention selection passed (**84 discovered, 3 selected, 0 failures**). `MIX_ENV=test mix format --check-formatted` passed. Checks used the isolated `storyteller_test` database and deterministic fake providers; no live model request, OAuth consent, or campaign data was used.

## 2026-10-07 — Default the GM to Luna and protect model allowance

- New installs and existing unset model preferences now default to `gpt-6-luna`. Automatic remains available as an explicit setting and continues to follow the account catalog order.
- Repository agent guidance requires fake providers for development and automated tests, forbids routine live calls/catalog lookups/OAuth, and reserves live QA for owner-requested Luna runs. Sol/Astra comparisons require a separate explicit request.
- OpenAI lists GPT-6 Luna API rates below Sol and Astra; those API dollar rates do not describe ChatGPT plan usage allowances. The default follows the owner's cost/allowance direction without promising a specific reduction in plan usage.
- **Verification:** full isolated WSL suite passed (**531 tests, 0 failures**), including settings, connected-account selector, and turn-submission checks. `MIX_ENV=test mix format --check-formatted` and `git diff --check` passed. All model behavior used test fixtures/fake providers; no live model call, catalog request, OAuth consent, or campaign QA data was used.

## 2026-10-07 — Verify inspection findings across a direct follow-up

- Extended the production-boundary fake-provider regression from a single action to a two-turn inspection and Ask GM sequence. The scene canon establishes an eastern chart but has no mark details; the inspection adds a visible scratch without asking the player to describe it, and the lasting finding records that author and timing are unknown with provenance to the inspecting turn. A direct follow-up asks who made it and when; the response preserves that uncertainty and creates no new continuity entry.
- The test uses `Play.submit_turn` and the isolated ExUnit database only. It verifies Storyteller assembles the policy, includes the observation in follow-up history, and commits finding provenance; it cannot establish that a live model will follow the same instructions.
- **Verification:** full WSL `MIX_ENV=test mix test --max-cases 4` passed (**530 tests, 0 failures**); the focused two-turn regression passed (**1 selected, 126 excluded**). `MIX_ENV=test mix format --check-formatted` and `git diff --check` passed. No live model request, OAuth consent, or connected campaign/session access was used.

## 2026-10-07 — Repair player-voice agency violations precisely

- The saved player action is the sole source of player dialogue and activity. Ordinary GM proposals that try to add either as a player-speaker event now fail validation as a player-agency violation and get a focused correction so the provider can repair the turn without asking the player to repeat their move. Time-passage turns keep their broader agency guard.
- The repair remains narrowly scoped: it does not block validated GM-adjudicated player-character facts such as an injury, nor ordinary NPC dialogue. Fake-provider regressions cover an invented PC line followed by a corrected response and a separate accepted consequence with NPC dialogue. This verifies the server boundary and correction guidance, not live-model compliance.
- **Verification:** full WSL `MIX_ENV=test mix test --max-cases 4` passed (**530 tests, 0 failures**); the focused agency regressions passed (**127 discovered, 2 selected, 0 failures**) and the existing time-passage agency regression passed separately. `MIX_ENV=test mix format --check-formatted` and `git diff --check` passed. All provider behavior used fake responses; no live model request, OAuth consent, or campaign data was involved.

## 2026-10-07 — Keep transient turn recovery automatic

- The player no longer hits a fixed four-claim ceiling for safe transient LiveView failures. Network drops, incomplete streams, provider-unavailable responses, and long receive timeouts retry the same saved turn with exponentially increasing waits capped at five minutes. The first four claims retain quick in-claim retries; later cooldowns use a single half-open probe. The submitted action and roll stay attached to that turn; only one accepted proposal can commit.
- Provider 5xx, service-unavailable, overload, and rate-limit errors now have a distinct retry classification. Usage/authentication, unknown account status, context-size corrections, and invalid proposals remain deliberate intervention paths. Unexpected resolver exits are marked separately and recover the same turn when the session reconnects.
- Added coverage for recovery beyond four claims, provider 503 classification, and automatic resumption of a failed transient turn after reopening the session. Recovery checks plan availability before each claim and keeps the existing ownership fences.
- **Verification:** focused WSL regression selection passed (240 tests, 0 failures; 233 excluded across the selected files), covering provider 503 classification, recovery beyond four claims, a single half-open probe, LiveView resume after four claims, duplicate-worker fencing, and the opening-scene retry. Existing retry and connected-play tests use isolated fictional/test fixtures; no live model request or OAuth consent was involved.

## 2026-10-07 — Keep NPC findings in their own dialogue

- Clarified the shared GM contract: narration can establish the moment or visible action before a present NPC's factual line, but should not summarize the same finding immediately beforehand. Natural introductions and direct character dialogue remain encouraged.
- Extended the fake-provider request-boundary test to assert this anti-echo guidance reaches the assembled request. It proves prompt delivery only; matched human review is still needed to judge generated prose and pacing.

## 2026-10-07 — Keep transient failures on the saved turn

- A live Quiet Observatory turn completed after about 30 seconds. Around the ten-second mark, the in-progress page briefly showed an account-usage warning saying requests were held even though the saved turn was still resolving. The message now distinguishes new requests from a request already in progress; English, Spanish, and French copy are covered by LiveView tests.
- After the existing four quick provider retries per claim, safe transient network, incomplete-stream, and server errors now receive up to three further same-turn claims with 1/2/4-second backoff. Account usage is checked again before every claim; limit, authorization, long-timeout, and proposal-correction failures do not enter this loop. If recovery is underway, the board says Storyteller is retrying automatically, keeps the action visible, and hides the manual Retry control. A failed transient turn also resumes this bounded recovery when the session is reopened. An unexpected local resolver exit releases its claim and resumes the same saved turn when it is still eligible.
- Added Play and LiveView regressions that exhaust the quick retry budget, hold the automatic retry open for inspection, then complete the original action. They verify one saved player action and one GM narration, no second retry worker, opening-scene recovery, and same-turn recovery after a worker exit. Usage-status copy now clarifies that a request already in progress may still finish. Persistent outages still reach the same-turn Retry control after four claims; this is bounded recovery, not an unlimited background service.
- **Verification:** WSL `MIX_ENV=test mix test` passed (**526 tests, 0 failures**); focused retry regressions passed (**6 selected, 0 failures**), localization tests passed (**2 tests, 0 failures**), `MIX_ENV=dev mix compile --warnings-as-errors`, `mix format --check-formatted`, and `git diff --check` passed. The campaign-editor test that once redirected under parallel suite load passed in isolation and on the repeated full run. Live QA used only the isolated fictional Quiet Observatory database; no Vineyard data was accessed.

## 2026-10-07 — Retry fast provider timeouts automatically

- Req reports both a fast connection timeout and an idle response-stream receive timeout as `:timeout`. Storyteller previously treated both as the long-timeout case, so a quick transport hiccup got only one automatic retry before the player saw Retry.
- The local HTTP boundary now distinguishes fast timeouts from the configured receive-timeout interval on the Responses route only. The stream parser tracks idle time from the last SSE chunk, so an active long response followed by a quick disconnect still gets the transient retry budget. Fast timeouts before response headers and during body enumeration use the four-retry network recovery path; a genuine 90-second idle receive timeout retains its single retry. OAuth and other unmarked HTTP callers keep their old timeout classification. Any body timeout discards partial stream content.
- Added adapter and Play regressions for fast timeouts before and after headers, elapsed receive timeouts, and a player action that survives four actual Req transport-timeout failures before completing exactly once. Its action, narration, and world-time change each appear once; no roll or state change is duplicated.
- **Verification:** full WSL `MIX_ENV=test mix test` passed (**524 tests, 0 failures**); focused auth/OpenAI/Play tests passed (**156 tests, 0 failures**); `MIX_ENV=dev mix compile --warnings-as-errors`, `mix format --check-formatted`, and `git diff --check` passed. No live provider/OAuth requests or Vineyard data were used. Req exposes the same timeout reason for both phases, so the boundary uses elapsed idle time with a 500ms/5% margin; the tests inject 150ms instead of waiting 90 seconds.

## 2026-10-07 — Keep player moves out of the retry loop

- Product direction: a player must not lose momentum or act as the operator for transient provider failures. A single fast retry followed by a hard failure is not acceptable. Keep the original move and roll in the active turn, make recovery automatic when the fault is transient, and ask for player intervention only when there is a meaningful action to take (for example, resume a paused account or correct oversized local context). Bounded retries still need account and duplicate-event safeguards; presenting a same-turn retry after exhausting recovery remains a known V1 P0 gap, not a solved UX.
- A matched same-action QA probe on the isolated Quiet Observatory checked a lantern-lit inspection of a stopped clock with its cause unresolved. GPT-6.1-Sol low effort produced a valid response on its first proposal in 24.85s (7.83s to first output). GPT-6-Luna low effort took two automatic correction attempts before producing a valid response in 43.19s (1.51s to first output); a one-retry ceiling would have surfaced a failed turn before its successful third proposal. Both kept the clock at 8:46, reported no audible ticking during the minute, and left the cause unknown. This is one matched action, not a model-quality verdict or a latency distribution.
- **Verification:** the paired live turn used two cloned campaigns in `storyteller_quiet_observatory_20261007_codex1` only. Both cloned turns completed; their source fictional campaign remains unchanged. No Vineyard or ChatGPT source data was accessed, and no OAuth consent was completed.

## 2026-10-07 — Keep gameplay QA on independent fiction

- Replaced plan steps for Vineyard source-share review, campaign reconstruction, and an approved import with the current preservation boundary: never access, continue, import, or test against the source or a comparison copy.
- Manual and automated gameplay QA use independently authored fictional campaigns such as the Quiet Observatory. Generic vineyard genre examples and the Finca–Bodega route/presence lesson remain abstract product scenarios.
- **Verification:** documentation-only review; `git diff --check` passed. No campaign data or model calls were accessed.

## 2026-10-07 — Let invited ensembles finish a scene beat

- Removed the default two-bubble NPC cap from GM instructions. Concision now follows the beat, while an invited ensemble can give each relevant present character a distinct reaction before the handoff.
- Expanded the sensory scene request-boundary regression to invite three co-present characters and preserve their distinct replies in one turn. Campaign canon and player agency rules are unchanged.
- **Verification:** isolated WSL `MIX_ENV=test mix test test/storyteller/play_test.exs:1773` passed (**1 selected, 120 excluded**). The fake provider checks the assembled request and accepted event sequence; it does not test live-model prose compliance.

## 2026-10-07 — Keep active-turn feedback responsive

- Submitting a player action now renders the saved pending turn directly from the inserted record, without rebuilding the campaign projection and recent timeline first. While a GM response is pending, the 1.5-second LiveView poll reads only the active turn; it refreshes the board and story timeline once a completed, failed, or roll-waiting state needs to be shown.
- Added a LiveView regression that holds the fake GM response open, verifies the saved action stays visible, exercises an in-flight poll, and observes that neither operation queries the story-event table. The fake response is released and shown normally after commit.
- Internal proposal recovery now allows four brief retries for transient provider errors and fast transport failures, two extra requests to repair malformed or rejected proposals, and one retry after the explicit 90-second receive timeout. Req transport timeouts remain distinct from fast network disconnects, so a refused/closed connection does not inherit the long-timeout cap. The pending turn remains visible during recovery, so brief provider hiccups do not send the player to a retry button. Before every resend, Storyteller confirms the account is still available and the worker still owns the active turn attempt, avoiding calls after a usage pause or reconnect has superseded that attempt. Only after bounded recovery is exhausted does the saved turn surface its soft retry control.
- Updated request-envelope regression helpers to count the same low-reasoning field the provider sends, and aligned the account-page copy tests with the current, localized reasoning setting. Retry regressions cover multiple silent fast-failure recoveries, timeout recovery without duplicate D20 rolls/events, and the final same-turn retry control.
- Canonical elapsed minutes now advance recognizable in-world date/time labels in the saved world state and GM event timestamps, including midnight rollover. The board and next GM request derive the same current clock for existing saves that have elapsed time but still carry their original time label. ISO plus English, Spanish, and French date formats are supported; unknown free-form labels remain as authored.
- A connected, isolated Quiet Observatory play sample found context load/build under 0.12 seconds and commit at 4–7 milliseconds. Automatic GPT-6.1-Sol at low reasoning streamed its opening scene in 32.8 seconds and a later action in 34.2 seconds; manually selected GPT-6-Luna at low reasoning streamed a focused question in 7.2 seconds, an action in 8.9 seconds, and a one-hour passage in 9.1 seconds. Both produced coherent, continuity-aware answers in these small samples, but they were not matched turns, so this does not establish a quality-equivalent default. The QA campaign, account preference, and session live only in a fresh `storyteller_quiet_observatory_20261007_codex1` database on port 4017; the Vineyard database and campaign were not accessed.
- **Verification:** focused HTTP and OpenAI adapter tests verify that Req `:econnrefused`/`:closed` remain fast `:network_error`s, while its explicit `:timeout` stays distinct. The quick-recovery LiveView regression passed with three consecutive transport disconnects followed by a successful response: the saved action remained visible and no manual retry UI appeared. The existing exhaustion/idempotency regression passed with four internal quick retries before the same-turn UI retry was offered. Full WSL suite: `MIX_ENV=test mix test` — 520 tests, 0 failures. The live QA actions above used only the separate fictional campaign; no OAuth consent was completed.

## 2026-10-06 — Run Storyteller in Docker

- Added a multi-stage production release image and Docker Compose setup with PostgreSQL, startup migrations, persistent database and ChatGPT credential volumes, and port 4000 published on `0.0.0.0`.
- Production listener binding is configurable with `STORYTELLER_BIND_ADDRESS`; it remains loopback by default and the Docker image selects `0.0.0.0`. Added environment variable examples and Docker startup instructions to the README.
- **Verification:** `git diff --check` passed. Docker and Erlang are unavailable in this environment, so image build and application startup could not be verified.

## 2026-10-06 — Reduce GM wait and retry transient provider failures

- Requests now ask recognized GPT-5, GPT-6, and o-series models for low reasoning effort. Other models keep their defaults, and account settings explain the behavior.
- GM generation gets up to two internal retries after a brief 300 ms pause for invalid responses, provider errors, incomplete streams, timeouts, and proposals rejected during decoding, validation, or final campaign-state checks. A rejected proposal adds concise, rule-specific correction guidance to the next GM request; the player-facing failure stays generic if recovery is exhausted. Usage-limit, authorization, capability, and local context failures still surface immediately. Nothing is committed until a proposal passes validation.
- **Verification:** tests and live model calls were not run. The ChatGPT-plan preview limitations do not list `reasoning` among unsupported Responses fields; OpenAI's reasoning guide says lower effort favors speed and token use, with a possible quality tradeoff.

## 2026-10-05 — Keep sensory observations inside the character's vantage

- The history retriever recognized common looking verbs but missed Rioplatense “mirá” and tasting verbs. Those actions could fall through to broad keyword search, which risks pulling a same-word description from a place the character cannot observe.
- Added common voseo look/tasting forms plus English and French tasting verbs. Extended the isolated same-turn travel/inspection regression with a “mirá” query and English, Spanish (“probá”), and French (“goûte”) tasting queries. The archive decoy uses the matching door/wine/cup words; the expected destination observation is retained while the unvisited archive details stay out.
- Updated the active story-quality and UX acceptance guidance. **Checks:** full isolated WSL suite passed (**513 tests, 0 failures**), including the expanded language/retrieval regression; warnings-as-errors compile, format check, Gettext freshness, and `git diff --check` passed. Synthetic test data only; no campaign QA data or live model request was used.

## 2026-10-05 — Keep focused sensory descriptions at the depth the scene needs

- The shared GM policy's “State 1-2 senses” wording could be read as a hard cap on every observation, including focused inspection and tasting. Clarified that one or two details are only a ceiling for sparse ambient texture; descriptions of an inspected target should provide enough action- and vantage-grounded evidence for the player to react.
- Kept the boundary around clues and canon unchanged: ambient texture does not create clues or causes, and inspection may reveal present evidence without inventing unsupported history. Added a request-contract regression and aligned the active story-quality and UX acceptance guidance. Compressed redundant sensory-agency wording to keep the common GM request under its 11,000-byte budget.
- **Checks:** the full isolated WSL suite passed (**513 tests, 0 failures**); warnings-as-errors compilation, format check, Gettext freshness, asset build, and `git diff --check` passed. Fake-provider tests verify the request contract and its byte bound, not live generated prose. No campaign QA data or live model request was used.

## 2026-10-04 — Give time-passage narration the canonical minimum

- When the saved time-passage input contains one clear numeric duration, the GM instructions now include its derived in-world minutes and explicitly ask the narration and structured response to cover at least that span. This shares the same minimum already enforced by the server-side world clock and leaves room for a longer canonical travel floor.
- Expanded the existing fake-provider regression to assert the 21-day duration appears as 30,240 minutes in the GM instructions and stays below the time-passage byte guard. This makes intent clearer to the model; it does not establish live prose compliance.
- **Checks:** the focused time-passage regression passed (**1 selected, 119 excluded**), including the 12,000-byte instruction guard; full isolated WSL suite passed (**513 tests, 0 failures**). Warnings-as-errors compile, formatter, Gettext freshness, asset build, and `git diff --check` passed. Fake-provider tests only; no live model request or campaign QA data was used.

## 2026-10-04 — Keep explicit time-passage duration authoritative

- A time-passage request with one clear numeric span in minutes, hours, days, or weeks (English, Spanish, or French) now determines the minimum elapsed world time. The server applies that value before validating the GM's proposed clock field, so an inconsistent zero or shorter value cannot reject or silently compress an explicit player request. Canonical travel time remains a lower bound.
- Vague, qualified, conflicting, or unsupported durations remain GM-directed; an explicit span beyond the clock limit is rejected recoverably. Tests cover localized units, ambiguity, bounds, and a fake GM returning zero for a clear 21-day request. No live model request was made.
- **Checks:** the final isolated WSL suite passed (**513 tests, 0 failures**), including parser edge cases and the zero-duration fake-GM regression. One earlier full run had two unrelated campaign-editor/session LiveView setup failures; both passed when selected directly, and subsequent full runs passed cleanly. Warnings-as-errors compile, formatter, Gettext freshness, asset build, and `git diff --check` passed on the final source. No live model request or campaign QA data was used.

## 2026-10-04 — Keep time-passage instructions focused

- The time-passage addendum repeated duration, travel, player-agency, and dice rules already present in the shared GM policy. Replaced those repetitions with a compact scene-scale instruction: routine work resolves as a montage; a closely followed live event remains moment by moment; stop at a meaningful decision.
- Updated fake-provider regressions to check the shared exact-duration rule, the intent-specific pacing, and the accepted two-minute football-match advance. The common/action instruction bundle remains under its 11,000-byte guard; the added time-passage pacing is checked under 12,000 bytes. This reduces repeated instruction text; it does not establish lower response latency or live prose compliance.
- **Checks:** targeted instruction-budget and pacing regressions passed (**3 selected, 117 excluded**); full WSL suite passed (**510 tests, 0 failures**). Warnings-as-errors compile, format check, Gettext freshness, asset build, and `git diff --check` passed. Synthetic test data only; no campaign QA data, live model request, or OAuth flow used.

## 2026-10-04 — Keep dense tracked resources compact on the play board

- Resource groups with more than four fields now show four at a glance and place the remaining rows in a native, closed-by-default “See more” disclosure. A shared LiveView component keeps values, last-change receipts, and canon-correction links identical in both locations.
- Expanded the existing 18-field stress regression to verify all rows remain present, later values and their correction action stay inside the disclosure, and the disclosure starts closed.
- **Checks:** full WSL suite passed (**510 tests, 0 failures**); warnings-as-errors compile, format check, Gettext freshness, asset build, and `git diff --check` passed. The test proves markup and data retention, not actual viewport geometry; 1280×720 browser measurement remains open. No live campaign or model request was used.

## 2026-10-04 — Match scene pace to routine work or close-up live play

- Clarified the adaptive-pace contract: routine work and waits cover the requested span as a montage, while a player who follows a live event closely can keep it at moment-by-moment scale. The close-up pace never authorizes the GM to decide the player's follow-through.
- Added a fake-provider behavioral test for a play-by-play football match during a time-passage turn; it verifies the request preserves the exact player wording and that the accepted response advances only its stated two game minutes. Existing multi-day coverage continues to verify routine work resolves at montage scale.
- Kept the live-event exception in time-passage-specific guidance, so ordinary turns do not carry extra prompt text or token cost.
- **Checks:** focused story, pacing, and voice regressions passed (**162 tests, 0 failures; 158 excluded**); full WSL suite passed (**510 tests, 0 failures**). Warnings-as-errors compilation, formatter, Gettext extraction freshness, asset build, and `git diff --check` passed. All tests used fake providers and test data; no connected QA campaign, model request, or OAuth flow was used.

## 2026-10-04 — Let direct answers finish without a stock invitation

- The Ask GM follow-up guidance required a “low-pressure next step” even when a direct answer was complete. It now allows that suggestion only when the answer creates a concrete, useful opening; otherwise it ends naturally. The focused look-around fixture is a complete standalone observation, and the request contract rejects generic closers.
- One connected Ask GM check in the separate Quiet Observatory campaign asked what a chart's epoch establishes. The GM answered the exact question, left the unresolved observation date uncertain, and did not append a generic invitation. The world clock remained at 06:07. This is one live prose sample, not proof of general model compliance.
- Safe stage telemetry for that isolated request recorded context load/build at 34/17 ms, OAuth access at 0 ms, model resolution at 851 ms (catalog cache miss), first text at 2,139 ms after Responses dispatch, provider stream at 15,795 ms, proposal validation at 22 ms, and commit at 6 ms. First-text time is inside provider-stream time. Completion was first checked by a later browser poll, so no exact submit-to-visible-completion latency is claimed.
- **Checks:** the focused Play request-contract test passed (**1 selected, 118 excluded**). The live check used only the isolated QA campaign and one ChatGPT-plan request; no Vineyard source or state was read or changed.

## 2026-10-04 — State the sensory-authority boundary in plain language

- Tightened the GM request contract to say that the GM supplies observable sensory facts before inviting the character's reaction, and may ask for judgment only after presenting evidence. It now explicitly calls out “What does it taste like?” as a question to avoid.
- Clarified the nearby clue rule: ordinary ambient texture is not itself a clue or cause. Clues can arise from an established premise or in-scene action, then become public continuity if they matter later; off-scene or retroactive evidence remains disallowed.
- Expanded request-contract regressions to assert the sensory handoff and clue-grounding language.
- **Checks:** focused Play and context-budget suites passed (**159 tests, 0 failures**); the full suite passed (**509 tests, 0 failures**). Warnings-as-errors compilation, formatter, Gettext extraction freshness, asset build, and `git diff --check` passed. Tests verify what Storyteller sends; they cannot establish that every model response follows the instruction.

## 2026-10-04 — Let the GM author evidence found through inspection

- A read-only review of the fictional Quiet Observatory QA session exposed an old investigation turn where the GM stopped at “the supplied canon does not specify” and asked the player to establish chart markings. That makes the player author an external fact the GM should reveal through the character's chosen inspection.
- Clarified the prompt boundary: when an established target is inspected, the GM authors observable present evidence from the action and vantage, even when the exact result was not prewritten. Unsupported cause and off-scene history remain unknown; a lasting finding may be proposed as public continuity. This separates newly observed evidence from invented history.
- Extended request-contract assertions beside the existing event-provenance regression for an action-grounded finding. The added wording was kept under the 11 KB instruction guard by compacting duplicated voice phrasing; no state or validation rule was loosened. No live provider request was made; the QA session was read-only and no new campaign/session was opened.
- **Checks:** focused Play/context-budget tests passed (**159 tests, 0 failures**); full WSL suite passed (**509 tests, 0 failures**). Warnings-as-errors compilation, format check, Gettext freshness, asset build, and `git diff --check` passed. Tests verify the contract and persistence boundary, not live-model compliance.

## 2026-10-04 — Inspect tracked-resource wrapping in isolated QA

- A disposable 1280×720 Quiet Observatory QA view with 18 tracked text fields showed wrapping and internal scrolling, with no overlap observed. The content felt dense, so that layout still merits polish.
- The reported campaign-37 overlap was not reproduced or inspected. Only the temporary campaign in the isolated 4003 QA database was used, and it was deleted afterward. Opening its new session auto-started one GM opening turn; this was an unintended test side effect, now stopped and removed with the disposable campaign. No player move was submitted, and QA campaign 1 remained unchanged. The separate Vineyard campaign and port 4000 were untouched; no further provider request was made.

## 2026-10-04 — Redact credentials from Phoenix parameter logs

- Local Phoenix request and WebSocket logs include parameter maps. Added recursive parameter filtering for OAuth codes/states, CSRF values, credentials, tokens, and authorization data, while leaving ordinary parameters available for development diagnostics. Application-specific GM timing metrics remain visible.
- Added an ExUnit regression that confirms nested and top-level auth parameter values are replaced and a harmless page parameter remains readable. Restarted the isolated port-4003 QA server and confirmed the socket log shows the CSRF field redacted. No credential values are committed or included in diagnostics.

## 2026-10-04 — Preserve long tracked-resource text in LiveView

- Added a synthetic LiveView regression for long unbroken text plus multiline values with intentional indentation. It verifies the content is preserved exactly and retains wrapping/whitespace classes.
- The fixture did not reproduce a current visual overlap, so no additional markup or CSS change was justified. DOM assertions do not verify browser geometry; the previously fixed full-width layout remains the known visual correction.

## 2026-10-04 — Connected Quiet Observatory story-quality spot check

- One turn completed through the current ChatGPT-plan connection in the separate fictional Quiet Observatory QA campaign. The GM described one coherent chart-analysis beat followed by two distinct NPC reactions, kept uncertain dates/identities unresolved, preserved earlier evidence, and did not invent a player reaction or unrelated canon change.
- The next investigative lead was left implicit rather than posed as a formulaic final question. This is a useful player opening, but prompts-to-decision still needs matched review across routine work, focused inspection, and ensemble scenes.
- The service-level turn took **35.6 seconds** end to end. This single observation is not a latency benchmark and did not measure first-token time or LiveView streaming/reveal behavior. Treat it as a latency signal to investigate while continuing story-quality review, not as proof that the experience matches in-chat ChatGPT.
- **QA:** one authorized provider call, turn 25 in the dedicated isolated QA database; no other campaign was read or modified. No code or canon logic changed.

## 2026-10-04 — Escalate repeated GM context-size rejections

- A lookup follow-up can exceed Storyteller's exact serialized-byte guard after the first GM request has already been sent. Retrying the same action previously rebuilt the same full-context request, so the model could ask for the same lookup and hit the same local guard again. A provider may also reject the compact retry; offering the identical compact request again does not make progress.
- The first recovery click for either size failure now applies the compact scene projection and a 48,000-byte request cap. If that is rejected again, the following click sends a minimal current-scene packet with omissions marked as unknown and bounded read-only lookup available. Canonical source data remains unchanged, and exact serialized-size checks remain in force. The localized error card labels compact and minimal retries, using the same saved action without duplicate timeline events.
- Added behavioral LiveView regressions for the oversized follow-up and repeated provider-window rejection; they verify the compact and minimal request envelopes and confirm only one player-action event after success. Extended English, Spanish, and French recovery assertions.
- **Checks:** the two focused recovery regressions passed (**79 discovered, 0 failures**); the complete isolated WSL suite passed (**507 tests, 0 failures**). Warnings-as-errors compilation, formatter check, Gettext extraction freshness, and `git diff --check` passed. All fixtures used `storyteller_test` and fake providers; no connected campaign, live model request, or OAuth flow was used.

## 2026-10-04 — Recover from provider context-window rejections

- A provider can reject an exact serialized request because it exceeds the selected model's context window, even when Storyteller's byte preflight accepted it. Recognize the documented `context_length_exceeded` code separately from local size failures and account usage pauses.
- Keep the turn/action saved and canon unchanged. The play page offers a clear retry action that rebuilds a compact, scene-focused projection: it shortens history to four recent beats and compact excerpts, trims long reference detail, preserves the player action and scene anchors, and marks omitted detail. The retry uses a 48,000-byte request cap, leaving room for the bounded lookup reserve; the adapter still exact-checks the outgoing body. This is byte-based recovery, not calibration of provider token limits.
- Added adapter, Play, and LiveView regressions for the provider error mapping, localized recovery, saved-action idempotency, and a genuinely smaller retry request. The compact path preserves canon in storage and writes exactly one player-action event after a successful retry.
- **Checks:** targeted WSL provider/Play/LiveView regressions passed (**224 discovered, 3 selected, 0 failures**); the full isolated suite passed (**505 tests, 0 failures**). Warnings-as-errors compilation, formatter check, Gettext freshness, asset build, and `git diff --check` also passed. Tests use `storyteller_test` with synthetic data and fake providers; no real campaign, OAuth consent, or live model request was used.

## 2026-10-04 — Reassure players during a long GM wait

- Recent isolated connected turns took 42–71 seconds; the application withholds generated text until the complete response passes validation and commits. A static wait card did not reassure the player once that delay stretched on.
- After 15 seconds, the active LiveView adds a localized note to the existing progress card. The copy works for an opening scene as well as a player-submitted move, keeping any submitted action visible and saying the complete checked GM response will appear when ready. It adds no story event, changes no turn state, makes no provider call, and reveals no partial text. Turn and worker fencing plus timer cleanup prevent a stale notice appearing after retry, completion, or session change.
- Added a fake-provider LiveView regression that waits through the real delay, checks a mismatched worker tag is ignored, verifies the saved action stays visible while reply text remains hidden, then confirms the note disappears after commit. English, Spanish, and French copy is present.
- **Checks:** focused WSL LiveView regression passed; the full isolated suite passed (**502 tests, 0 failures**); Gettext freshness passed. Test data stayed in `storyteller_test`; no real campaign, live model, or OAuth flow was used.

## 2026-10-04 — Set a soft dialogue default for ordinary solo actions

- The adaptive-pace instructions already asked the GM to avoid filler and include only warranted present-character reactions, but left the routine number of chat bubbles unspecified. Added a reversible prompt default: one cohesive GM passage and normally no more than two justified NPC speech bubbles for ordinary solo actions. Player intent and scene needs explicitly override it, preserving longer dialogue-led and ensemble scenes. There is no hard validator cap, truncation, or rejection path.
- Added a fake-provider request-boundary regression for the ordinary default, the override, and the longer-scene exception. This verifies only that guidance reaches the model request. The hypothesis still requires matched human play review to determine whether routine turns become less chatty without flattening ensemble play.

## 2026-10-04 — Open a fresh story timeline at its latest entry

- The initial `StoryTimeline` hook could scroll before the first connected LiveView/layout work had settled, leaving a fresh session at the campaign's oldest visible entry. Initial alignment now waits one additional animation frame and reads the final scroll height; it stops if the player has scrolled away, is cancelled on teardown, and is cancelled when a history prepend restores the reader's anchor.
- Added a fake-frame JavaScript regression that delays timeline growth between frames, then proves the initial viewport reaches the latest entry and does not yank a reader who moved away before alignment. Existing fake tests continue to cover prepended-history anchoring and reduced-motion reveal behavior. Composer and side-panel markup/CSS are unchanged.
- **QA:** A read-only check of the separate fictional Quiet Observatory campaign at 1280×720 reproduced the oldest-entry landing; manually scrolling reached the latest entry while the composer stayed in view. After the fix, a fresh reload in Codex's in-app browser opened at the newest story entry with the composer still in view. No action was submitted. Firefox retest remains pending.
- **Checks:** `mix assets.build` succeeded in WSL; bundled Node.js `--test assets/js/*.test.mjs` passed (**15 tests, 0 failures**); `git diff --check` passed. No model request or OAuth was used.

## 2026-10-04 — Give prose resources the full ledger width

- Long tracked resources of type `text` now span the compact play-board ledger instead of sharing a narrow column with another field. Quantities, money, status, and date fields keep the compact two-column layout.
- Added a rendered LiveView regression using 18 long text resources and a UX acceptance note for the full-width reading treatment.
- **Checks:** focused WSL LiveView regression passed (1 selected, 0 failures; 74 other tests excluded); warnings-as-errors compilation, formatter check, CSS build, and `git diff --check` passed. The final layout was not re-opened in a live browser after styling because opening a new development campaign auto-starts the GM and unexpectedly triggered one provider turn in a disposable visual-QA database. I stopped the server and dropped that temporary database; no existing campaign was accessed. Browser QA must use a fake provider or a fixture with its opening already completed.

## 2026-10-04 — Keep NPCs addressable by public role in oversized scenes

- A player may address a person by an observable descriptor (“the cook”) rather than a name. The emergency packet already prioritized explicit names and recent speakers, but could truncate that character from an unusually crowded scene.
- Scene-cast ranking now also matches the action against public character facts and current visible activity after explicit names and before recent speakers. It does not inspect private facts to infer an address and does not add hidden details to the packet.
- Added a synthetic 41-NPC regression: “ask the cook” keeps the person whose public occupation is cook and drops the last unprioritized observer while preserving the packet bound.
- **Checks:** focused WSL context-budget suite passed (**40 tests, 0 failures**); full isolated WSL suite passed (**500 tests, 0 failures**); warnings-as-errors compilation, formatter check, and `git diff --check` passed. Tests use synthetic data in `storyteller_test`; no campaign QA data, live model, or OAuth was used.

## 2026-10-04 — Match whole words when ranking canon by names

- Canon relevance previously counted a player-action word as a name match whenever it appeared anywhere inside a longer character or place name. In a crowded-scene fallback, saying “rose” could therefore prioritize “Rosetta” over an NPC actually addressed later in the same move.
- Name relevance now intersects normalized whole-word terms. This affects cast and place ranking as well as addressed-NPC prioritization; it does not add fuzzy, nickname, or semantic name recognition.
- Added a crowded-scene regression where “a rose” must not promote Rosetta, while the directly addressed Sera remains in the bounded packet and a stable-order observer is retained.
- **Checks:** focused WSL context-budget suite passed (**39 tests, 0 failures**); full isolated WSL suite passed (**499 tests, 0 failures**); warnings-as-errors compilation, formatter check, and `git diff --check` passed. Tests use synthetic data in `storyteller_test`; no campaign QA data, live model, or OAuth was used.

## 2026-10-04 — Distinguish an oversized lookup follow-up from preflight

- The adapter's exact body guard also runs after a model response requests a bounded, read-only campaign lookup. If the initial request fit but its continuation does not, the initial request has already reached the provider; it is inaccurate to present that as a pre-send failure.
- The adapter now preserves a separate context_followup_too_large failure code. The localized recovery notice says the first request was sent, only the follow-up was stopped by Storyteller's local size guard, no story or canon change was applied, and retry sends a new request. It does not display lookup payloads, invent diagnostics about contributing canon sections, or infer a usage charge. The initial compile-time size failure still says no request was sent and retains its numeric-only section diagnostics. Account usage pauses keep their separate UI state.
- Added exact adapter coverage that observes one Responses HTTP request and blocks the follow-up, a production Play.submit_turn fake-provider regression proving the distinct failure code, saved move, unchanged canon, same-turn retry, and no duplicate player action, plus LiveView recovery copy/preserved-action checks in English, Spanish, and French. The curation gate remains open for any essential data category without a useful safe correction path.
- **Checks:** focused adapter, Play, and LiveView regressions passed; the complete WSL suite passed (**501 tests, 0 failures**). `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix gettext.extract --check-up-to-date`, and `git diff --check` passed. Tests use synthetic fixtures and `storyteller_test`; no live provider, OAuth, or campaign QA data was used.

## 2026-10-04 — Keep an addressed NPC in the compact context fallback

- If an unusually crowded present scene exceeded the emergency retrieval packet's 32-NPC cap, simple source-order truncation could omit the person the player had just addressed. Although the read-only lookup could recover them, that made a direct exchange depend on an extra model lookup.
- The compact packet now prioritizes NPCs named in the current action, then recent speakers, and then preserves the previous stable cast order. The full cast stays server-side and available to the scoped lookup; the packet still marks that its scene cast is truncated.
- Added a synthetic behavioral regression with 41 present NPCs: the addressed NPC survives while the final unprioritized observer is omitted, the player is retained, and the request remains within its configured byte bound. This only improves a crowded emergency packet; it does not raise the cast cap or prove general name recognition.
- **Checks:** focused WSL context-budget suite passed (**38 tests, 0 failures**); full isolated WSL suite passed (**498 tests, 0 failures**); warnings-as-errors compilation, formatter check, and `git diff --check` passed. Tests use synthetic data in `storyteller_test`; no campaign QA data, live model, or OAuth was used.

## 2026-10-04 — Refresh the campaign-engine benchmark

- Rechecked current official pages for Friends & Fables, World Anvil, LegendKeeper, and Apple's design principles. The focused review adds the AI campaign-engine distinction described by Friends & Fables' 2024 ACE-1 announcement, its context-selection and per-message inspection pattern, and the age of those claims; the 2026 homepage remains separate evidence of current product positioning.
- Updated product guidance to keep Storyteller's local canonical engine separate from the GM voice, preserve durable canon while retrieving selectively, keep private context private in diagnostics, and make intent-sensitive pacing a tested behavior rather than another default control. The wiki/map comparison reinforces a scene-first player surface with deeper reference available when needed.
- No product behavior changed. Desk research only; no competitor account, user campaign, or live model was used.

## 2026-10-04 — Normalize accented canon retrieval

- Memory relevance and bounded campaign lookup now normalize query and searchable text to Unicode NFC. A word typed with decomposed accent marks matches canon stored with composed accents, and vice versa; long-record excerpts still center the matching fact.
- Added a behavioral regression for both forms through durable memory selection and the campaign-scoped lookup tool. This preserves player-facing canon as authored in storage except for normalized excerpts; it does not broaden the curated vocabulary or claim semantic synonym search.
- **Checks:** isolated WSL context-budget suite passed (**37 tests, 0 failures**); full isolated suite passed (**497 tests, 0 failures**), as did warnings-as-errors compilation, formatter check, and `git diff --check`. Tests use synthetic data in `storyteller_test`; no QA campaign data, live model, or OAuth was used.

## 2026-10-04 — Make character voice guidance actionable

- Strengthened the runtime GM policy to ask for distinct per-speaker word choice and rhythm, with accent carried naturally in the campaign language. It explicitly avoids phonetic spelling, caricature, repeated catchphrases, and mannerism spam while keeping quirks selective.
- Kept the instruction concise and below the existing 11,000-byte policy cap. Behavioral coverage checks the guidance reaches the real request after history compaction and that each present NPC's own voice fields stay attached to its stable speaker ID.
- Updated the acceptance brief and plan to measure audible voice distinction in matched connected scenes; request-boundary tests cannot prove generated delivery. No live generation was run in this iteration.
- **Checks:** focused provider-boundary, compact-context, and policy-size regressions passed (153 tests discovered, 3 selected, 0 failures); complete isolated WSL suite passed (**496 tests, 0 failures**). The new phrasing stays below the existing 11,000-byte policy cap. Tests used synthetic characters and a fake provider; no live generation or campaign QA data was used.

## 2026-10-04 — Stress long-campaign transcript compaction

- Expanded the ordinary-play context-growth integration test from 36 turns in three sessions to 120 turns in ten sessions. Each fake GM response now adds roughly 1.6 KB of narration, building a substantially larger persisted transcript while every move still travels through the real local turn pipeline.
- The test measures the exact serialized request envelope on every turn and requires the fake provider to receive all 120 actions under the configured 64,000-byte preflight. It checks ordinary transcript growth across session boundaries; it does not establish a maximum campaign size, live provider acceptance, or story quality.
- **Checks:** focused WSL integration regression passed (**117 tests discovered, 1 selected, 0 failures**); the full isolated suite passed (**496 tests, 0 failures**), as did formatter and `git diff --check`. All data was synthetic and isolated in `storyteller_test`; no QA campaign data, live model, or OAuth was used.

## 2026-10-04 — Extend the campaign-growth guard across sessions

- The earlier request-size integration regression stopped at ten turns in one session. It now has a separate fictional campaign that completes 36 consecutive ordinary turns across three sessions using the real local turn pipeline and a fake provider.
- The test records each exact serialized GM request envelope and asserts all stay below Storyteller's configured 64,000-byte preflight. This checks that ordinary history growth across session boundaries does not cause a local size failure; it does not test generated-story quality, arbitrary campaign scale, or provider acceptance.
- **Checks:** the focused regression passed (117 tests discovered, 1 selected, 0 failures); full isolated WSL suite passed (**496 tests, 0 failures**), and test compilation with warnings-as-errors, `mix format --check-formatted`, and `git diff --check` passed. All rows are isolated in `storyteller_test`; no live model, OAuth, or campaign QA data was used.

## 2026-10-04 — Let players correct public objectives without changing the story

- Public objectives now have a small **Correct** action on the player board. Players can fix a title, details, or Open/Completed/Abandoned status with a required reason; the objective keeps its stable ID and visibility, updates in the matching board section, and appears in a separate before/after receipt.
- If objectives are the largest measured contributor to a local GM request-size failure, the recovery card opens the same objective correction panel while preserving the saved action. Opening or saving the correction makes no provider call, creates no fictional event, and does not advance the game clock. Private objectives do not appear in choices or player-facing receipts.
- Campaign backup schema v13 preserves and validates objective correction history, and older supported schemas remain importable. Updated backup version assertions accordingly.
- Added isolated service, backup, and LiveView behavior coverage for public/private filtering, audit receipts, recovery from a saved failed action, and unchanged story/time. Updated the plan and acceptance brief.
- **Checks:** complete isolated WSL suite passed (**495 tests, 0 failures**); `MIX_ENV=test STORYTELLER_DB_NAME=storyteller_test mix compile --warnings-as-errors`, `mix gettext.extract --check-up-to-date`, `mix format`, and `git diff --check` passed. Tests used synthetic campaign fixtures and fake providers only; no campaign QA data, live model request, or OAuth consent was used.

## 2026-10-04 — Point oversized-request recovery at the largest category

- The request-size recovery card previously offered only a campaign overview and setup editor, even when the largest section was inventory, resources, world state, or another record type. It now directs the player to the highest numeric contributor: setup editing; a preselected audited correction form for inventory, tracked resources, and world state; or the related scene, campaign-memory/objectives, or story section.
- Opening the correction form is a local UI action. It does not call the provider, change canon, or retry the turn. The saved action stays attached to the same failed turn. Diagnostics still include category names and byte counts only, never GM-private prompt text.
- Added a translated en/es/fr message and a behavioral regression that checks the saved action and retry remain intact in all locales, then opens the world correction panel on that same failed turn.
- This is a targeted review path, not full curation: scene/routes and read-only campaign references do not yet have edit controls that can safely reduce irreducible request size. That recovery gate remains open.
- **Checks:** the localized request-size recovery regression passed (**74 discovered, 1 selected, 0 failures**) and the complete isolated WSL suite passed (**491 tests, 0 failures**). Warnings-as-errors test compilation passed. All behavior checks used synthetic fixtures and the separate `storyteller_test` database; no campaign QA data, OAuth, or live provider was used.

## 2026-10-04 — Give oversized place and route context an audited correction path

- The request-size recovery card now maps the largest `places` or `travel_connections` section to the matching correction panel. Players can explicitly update a public place's name, description, and facts, or a public route's travel time and scene context; opening the form leaves the saved turn and story untouched.
- Correction choices include only public places and public routes whose endpoints are public. A correction revision-checks and audits its before/after state, changes the canonical record without creating a fictional event or moving game time, and is hidden from player-facing receipts if the record later becomes private.
- Campaign backup schema v12 preserves the new public correction records and validates their bounded fields and stable IDs; schema versions 1–11 retain their import behavior. The database constraint allows the new audit kinds and refuses a rollback that would discard saved corrections.
- Added behavior tests for public/private filtering, place and route changes, no fabricated story event or clock advance, backup round-trip, and category-specific LiveView forms on the same saved failed action.
- The recovery review still needs safe curation paths for any other oversized section that has no editing path; the app does not silently delete canon or trim player notes.
- **Checks:** complete isolated WSL suite passed (**493 tests, 0 failures**); focused place/route, backup, and session LiveView suites passed (**89 tests, 0 failures**); `mix compile --warnings-as-errors`, `mix format --check-formatted`, Gettext freshness, and `git diff --check` passed. Tests used synthetic fixtures and `storyteller_test`; no campaign QA data, OAuth, or live provider was used.

## 2026-10-04 — Keep the matching detail when retrieving long canon

- A lookup could rank long canon only after projecting it to the first 180 characters, so a fact buried later in a long note could be missed or omitted from the result even though the request named it.
- Search terms now flow into the visibility-scoped record projection. Oversized text fields return a short excerpt centered on a matching term when present, retain the truncation marker, and leave the original context untouched.
- Added a French regression with the requested detail deep in a long place description; it confirms the bounded excerpt contains the named fact and remains findable by the lookup.
- This improves one bounded lexical lookup path; unrelated paraphrase, semantic recall, and model behavior remain separate evaluation gaps.
- **Checks:** focused WSL `CampaignLookup` suite passed (**8 tests, 0 failures**); full isolated WSL suite passed (**491 tests, 0 failures**). Test compilation with `--warnings-as-errors`, formatter check, and `git diff --check` passed. All tests used synthetic data in `storyteller_test`; no campaign QA data, OAuth, or live provider was used.

## 2026-10-03 — Retrieval-first fallback for oversized GM context

- The exact-envelope fix prevented a second size check from rejecting a request after compilation, but a separate gap remained: if the required projected context itself could not fit, the compiler failed before the optional lookup could help.
- Added a last-resort retrieval packet for the production turn path. It preserves the player's action and interaction mode, the public current location/date/time/weather, the player and present cast, and bounded scene anchors. It labels all omitted canon as unknown; a request-scoped read-only lookup searches the original server-held campaign context when the GM needs an omitted fact. This does not mutate records or widen the requested campaign scope.
- Added a synthetic `Play.submit_turn` regression that forces fallback using 90 long off-scene place records and a 36,000-byte test ceiling. It verifies that the active scene reaches the fake provider, remote canon remains retrievable, a remote character is not mistaken for present, private character facts remain in GM-private lookup results, and source records remain unchanged. An additional lookup regression prevents characters in GM-private places from being exposed as public.
- Added a separate ten-turn `Play.submit_turn` behavior regression: ten ordinary consecutive actions all complete, and each exact serialized request stays below the 64,000-byte guard.
- Reserved 24,000 bytes for a bounded function continuation: up to 16,000 encoded completion-output bytes, the 6,000-byte lookup result, plus schema and framing. Exact serialized bodies are still checked before both provider calls; oversized tool completion output is treated as a provider-response failure, not misreported as campaign-context overflow.
- This closes the case where a large but retrievable canon projection fails before lookup. It does not prove that arbitrary essential prompt/action data can fit or that every model will always choose to call the tool. Matched latency/token and live narrative-quality comparisons remain acceptance work; no real campaign 37 data or live model request was used.
- **Checks:** WSL `ContextBudget`/`CampaignLookup`/`OpenAI` suites passed (**70 tests, 0 failures**); the lookup reserve and retrieval-packet Play regressions passed (**2 tests, 0 failures**); the ten-turn Play regression passed (**1 test, 0 failures**). The final complete isolated WSL suite passed (**490 tests, 0 failures**); `MIX_ENV=test mix compile --warnings-as-errors`, formatting, and `git diff --check` passed. Tests used only `storyteller_test`, synthetic campaign data, and fake providers. No live request or campaign DB was used.

## 2026-10-03 — Budget the exact GM request and strengthen long-campaign P0

- The user reports the local GM size guard blocking a short campaign. The named campaign/port was not opened or queried; the audit and regression use source code plus synthetic inputs in `storyteller_test`.
- The 64,000-byte ceiling is Storyteller's own configured guard, not a GPT context or ChatGPT Plus quota. The play policy contributes a fixed 11,307 UTF-8 bytes on each turn. The app already limits transcript history and applies relevance/detail compaction; it does not send the whole campaign transcript. A read-only status check of the isolated Quiet Observatory fixture found 24 completed turns and no stored failed turn; no turn was run and no rows changed.
- Found a size-accounting gap: the compiler previously counted instructions + the encoded context JSON + 512 bytes, but the adapter enforces the full outer JSON body, which escapes the already-encoded context again. The compiler could accept its compacted projection and then have the adapter reject it without another compaction pass.
- Added a shared request-envelope serializer to compile and enforce the same outgoing body size, including nested escaping, framing, and model slug. Automatic model choice budgets for a maximum 255-byte slug; longer catalog entries are excluded. Existing compaction now runs against the exact body size, with source canon unchanged.
- Updated the P0 rule: campaign age, transcript length, and unrelated records alone must not strand normal actions. Storyteller's database is the durable memory; the current HTTP route is stateless. Keep the first packet small, retrieve old canon selectively, and benchmark the local function lookup against app-side retrieval. The current lookup searches assembled in-memory canon and cannot help if that initial context fails to compile; hosted MCP/connectors are unavailable on this ChatGPT-plan route. If an irreducible limit remains, preserve the action/canon and offer app-assisted review/retry rather than a blind retry or routine note-pruning request.
- The remaining P0 work is to broaden synthetic long-campaign tests (including difficult quoting/locales), compare total request bytes and provider-reported tokens, and ensure the app-assisted path handles a truly irreducible active scene. This change fixes a proven envelope mismatch but is not a guarantee for arbitrarily large essential instructions or canon.
- **Checks:** focused WSL context-budget/OpenAI adapter suites passed (**61 tests, 0 failures**); campaign-scoped lookup reserve Play regression passed (**1 test, 0 failures**); the full isolated WSL suite passed (**485 tests, 0 failures**); warnings-as-errors test compilation, formatter, and `git diff --check` passed. Tests used only `storyteller_test`, fake providers, and synthetic campaign data. No live model request, OAuth flow, or vineyard data was used. The reported campaign 37/port 4000 was not opened or queried.

## 2026-10-03 — Reserve readable story space on laptop-height desktops

- The 1280×720 acceptance measurement showed only 116px of visible story history. The laptop-height play layout now keeps the story card at least 20rem tall; the story remains independently scrollable and the main column can scroll to the sticky composer and nudges. The wide player rail also scrolls independently when its board is taller than the viewport.
- Added a synthetic layout contract regression for the reserved story height, composer/nudge availability, and player-rail scrolling. The main-column scroll and sticky composer remain available when content exceeds the viewport; the player rail scrolls independently. The exact rendered viewport pixels still need browser visual verification.
- **Checks:** WSL layout tests passed (**2 tests, 0 failures**); the full isolated WSL suite passed (**484 tests, 0 failures**); formatter, asset build, and `git diff --check` passed. No campaign database was accessed and no GM request was sent.

## 2026-10-03 — Keep long tracked-resource headings inside the play board

- The player board already wrapped long field labels, units, and values, but a long unbroken campaign-panel name could still overflow the sidebar. Reused the resource-text wrapping rule on each panel heading.
- Extended the synthetic 18-row layout regression with a 72-character unbroken panel name and asserted its heading retains the wrapping class. This covers the reported category of layout failure without reading the imported campaign.
- **Checks:** focused WSL LiveView regression passed (**74 discovered, 1 selected, 0 failures**); asset build and `git diff --check` passed. Firefox and the protected campaign's exact overlap remain unverified.

## 2026-10-03 — V1 P0 context resilience: stress maximum bounded canon

- Added a synthetic stress case with 48 characters, 64 places, 48 public and 48 GM-private objectives, long descriptions, and named scene/travel anchors. The relevance and compaction pipeline produced a **42,050-byte** request against the **64,000-byte local preflight** while keeping the current scene, forty-minute travel link, named ledger facts in both visibility scopes, and original source canon intact.
- The regression exposed an emergency excerpt edge case: a short field allowance could be consumed entirely by the generic omission suffix, dropping the field's text. Short excerpts now retain up to 39 leading characters and use a single ellipsis; larger excerpts retain the explanatory marker. This preserves a bounded excerpt without changing stored canon.
- **Checks:** full isolated WSL suite passed (**483 tests, 0 failures**); focused maximum-canon regression passed (**34 discovered, 1 selected, 0 failures**); `mix format --check-formatted` passed. This synthetic shape does not establish a maximum campaign size or actual provider acceptance. No live request, OAuth, QA/development campaign, or vineyard data was used. App-assisted recovery for irreducible oversized canon remains open.

## 2026-10-03 — V1 P0 story quality: GM leads with concrete tasting observations

- Expanded the tabletop GM guidance so a tasting starts with the facts the character can perceive: appearance, aroma, palate, relevant fruit/acidity/tannin/body/sweetness, and finish. A present qualified expert may contribute, then the player is invited to react without being asked to invent sensory facts.
- Strengthened the synthetic tasting scene with an established 2028 wine in the room and a fuller observation before the character's question. The test checks that the prior state supplies the wine, the GM response covers the relevant sensory dimensions, and the player is asked for an opinion rather than to define the taste.
- **Checks:** full isolated WSL suite passed (**483 tests, 0 failures**). A fake provider verifies the sensory guidance and scene state at the request boundary, but cannot establish that live model prose follows it consistently.

## 2026-10-03 — V1 P0 story pacing: lead with evidence and limit repeated caveats

- A fictional chart-inspection review found that the GM can preserve uncertainty while repeating unchanged limits across turns, leaving the player to request each next observation. The runtime policy now leads with supported evidence, repeats a known limit only when new evidence changes it or a choice needs it, continues useful checks, and preserves lasting witnessed evidence as public continuity. Existing canon, uncertainty, player-agency, and bounded-task rules remain in force.
- Extended the fake-provider chart scenario with public place facts for two charts, visible reference stars, and a cracked eyepiece. Across two turns, the test confirms the prior cause caveat remains available in request history, the next check advances the investigation without repeating it, eight plus four minutes pass, and Mira offers a real next choice. This demonstrates the provider boundary's intended shape; it does not prove generated prose will follow it consistently.
- **Checks:** focused two-turn chart behavior and the 11 KB instruction guard passed (each: 114 tests discovered, 1 selected, 0 failures); layout regression passed (1 test); full WSL suite passed (**482 tests, 0 failures**). Test and dev compilation with warnings-as-errors, formatting, Gettext freshness, `mix assets.build`, and `git diff --check` passed. All test cases used synthetic fixtures in the isolated WSL test environment; no live provider, OAuth, vineyard data, or player campaign was used.

## 2026-10-03 — Keep the play composer reachable while scrolling

- Sized the desktop session board to the viewport so the story owns a bounded scroll area and the composer remains visible while players review older events.
- Added layout regression coverage. The WSL layout test passed (1 test, 0 failures), and the isolated Quiet Observatory board was visually checked at 1280×720 without submitting an action.
- Firefox-specific confirmation remains open because no Firefox browser was available; no campaign data was changed and no GM request was sent.

## 2026-10-03 — V1 P0: prevent campaign context from stranding a turn

- The recurring “required campaign details too large” message is Storyteller's own serialized-byte preflight, raised before an HTTP request reaches GPT. The configured 64,000-byte application guard is not a token count or a measured Plus/model limit.
- Kept the database as campaign memory and added a layered request policy: relevance projection, bounded continuity rows/history, prose/detail compaction, then a marked emergency compaction pass for oversized remaining strings. The saved player action and current date/time/weather/location anchors survive; canonical source records stay unchanged. The GM receives completeness flags so omitted details are treated as unknown.
- Added an optional request-scoped local lookup function for canon omitted from the opening context. It is only offered when the reduced request can reserve space for a tool result and continuation. The executor uses the already authorized campaign context, labels public vs GM-private results, cannot accept a campaign ID or widen visibility, and cannot mutate state. One call and a small result are allowed; exact serialized size is checked before both provider requests.
- A hosted MCP is not supported on the current ChatGPT-plan HTTP route. This uses the route's app-defined function/custom tool mechanism and replays the original input plus full response output for continuation; no provider-side conversation memory is assumed. See OpenAI's [SIWC preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) and [additional tools guide](https://developers.openai.com/api/docs/guides/tools-tool-search). Tool schemas, results, and round trips can increase token use and latency, so savings and narrative improvements remain unproven until measured on matched synthetic campaigns.
- When even the compact view cannot fit, the local adapter classifies that as a recoverable context-size error rather than a generic provider failure. Existing save/retry behavior remains in force; a polished category-specific edit/review flow for truly irreducible canon is still open.
- **Checks:** focused context/lookup/adapter/play suites passed (**179 tests, 0 failures**); the full isolated WSL suite passed (**482 tests, 0 failures**); `MIX_ENV=test mix compile --warnings-as-errors`, formatting, and `git diff --check` passed. No live model request, OAuth consent, or campaign database was used.

## 2026-10-03 — V1 P0: bound present-scene and long-lived canon growth

- The follow-up audit found three avoidable growth paths after transcript compaction: every endpoint in the travel graph could be treated as adjacent to the player, large profiles for co-present or mentioned characters had no field cap, and open objective details plus old objective rows could accumulate across the campaign.
- The compiler now treats only the player's current place and its directly connected routes as adjacent. It sends at most 64 place identities and five detailed place records, preserving the current scene and action/character-relevant locations first. Oversized descriptions/facts are compacted with an explicit completeness flag.
- Character context is limited to 48 identities and 12 detailed profiles, ranked by player identity, direct mention, recent speaker, scene presence, and relevant facts. Stable IDs, names, current place, and duty survive in retained identity rows; large facts and voice guidance receive per-field caps. The player, named/recent scene characters, and present cast are favored. Objective projections retain up to 48 rows per visibility scope and eight details, prioritizing named and recent open objectives; omitted details/rows are marked. Canonical records are never changed.
- A synthetic fixture starts above the 64,000-byte guard with 107 characters, 94 places, and 122 public/private objectives. It compiles within the configured bound while preserving the named NPC's French voice, her action-relevant private ledger fact in GM-only context, the current/directly connected places, and relevant objectives. A place two route steps away is no longer treated as adjacent. Input records remain unchanged.
- **MCP/retrieval investigation:** the current ChatGPT-plan Responses route supports app-defined function/custom tools but excludes hosted MCP/connectors; Storyteller's adapter does not dispatch tools today. Therefore direct hosted MCP is not a current implementation option. A local, campaign-bound, read-only function loop remains a measured follow-up experiment, not a replacement for the compact scene snapshot: tool definitions/results still consume input and each lookup adds a round trip. Keep full canon local, return visibility/provenance, and compare aggregate input, latency, and fact recall before adopting it.
- **Limit:** bounded projections make ordinary campaign growth safer, but there is no claim that arbitrarily large essential instructions or active canon can fit. The 64,000-byte value is still an application guard, not GPT's limit or an input-token count. The app-assisted review path for truly irreducible state and route-specific calibration remain open.
- **Checks:** ContextBudget WSL suite passed (**31 tests, 0 failures**); full WSL suite passed (**468 tests, 0 failures**); test-environment mix compile --warnings-as-errors, repository formatter check, and git diff --check passed. Tests used synthetic inputs and the isolated test environment. No campaign database, provider request, OAuth flow, or vineyard data was accessed.

## 2026-10-03 — V1 P0: bound growing world state and tracked-resource context

- A read-only audit found that transcript history was already bounded, while free-form public/GM-private world maps and the tracked-resource panel list could still be passed through without a useful count/size bound. These categories can grow independently of session history and exhaust the local guard.
- The request compiler now keeps public date/time/weather/location anchors, ranks other world keys by current action and scene terms, caps each visibility scope at 8,000 serialized bytes and 32 fields, and compacts oversized nested values. For tracked resources it keeps up to 32 fields, prioritizing action-matched rows plus a small stable baseline; oversized text values are excerpted. Canonical database data is not changed.
- Completeness flags now tell the GM when world or panel data is partial. The policy says omitted canon is unknown, not absent, and cannot be invented or changed. Synthetic regression fixtures exceed the 64,000-byte local guard before projection and verify scene anchors, action-matched world/resource facts, omission reporting, and unchanged source data.
- The supported route is stateless over HTTP (`store: false`, no `previous_response_id`). Official preview documentation permits app-handled function/custom tools but excludes hosted MCP/connectors. A local read-only function loop is a later experiment after this deterministic projection baseline; tool definitions/results and extra round trips must be benchmarked too.
- **Remaining work:** truly oversized essential canon can still exceed the guard. Continue testing longer multilingual campaigns, implicit recall, and the app-assisted remedy; do not silently discard records or raise the guard without route evidence.
- **Checks:** ContextBudget WSL suite passed (**30 tests, 0 failures**); the focused GM policy size regression passed (**1 selected test, 0 failures**); the full WSL suite passed (**467 tests, 0 failures**). No development/QA or vineyard database, live provider, or OAuth flow was used.

## 2026-10-03 — V1 P0: raise the interim local context guard

- Raised the configured application preflight from 24,000 to **64,000 serialized bytes** consistently for the default and every supported model ID. First-tier relevance projection still runs before size measurement; the increase therefore does not restore unrelated history or remote prose already omitted by the compiler.
- Added a pure synthetic regression for a relevant scene with a 10,000-character premise, a 10,000-character current-place description, and near-limit instructions. Its estimated request is exactly **31,825 bytes**: the configured default accepts it with the relevant premise and place intact, while an explicit 24,000-byte override rejects it. This verifies the local guard only; no provider acceptance or SIWC maximum is inferred.
- 64,000 is a bounded interim app guard selected to admit the known valid shape with margin. It is not a model context window, ChatGPT account limit, or verified ChatGPT-plan route ceiling. Route-specific calibration from safe aggregate provider usage and request behavior remains open; required canon is never silently dropped.
- **Checks:** the `ContextBudget` WSL suite passed (**28 tests, 0 failures**); the relevant Play request-context suites passed (**125 tests, 0 failures**) using the isolated `storyteller_test` database; and the full WSL suite passed (**465 tests, 0 failures**). WSL formatting checks and `git diff --check` passed. No development/QA or vineyard campaign database, live provider, or OAuth flow was accessed.

## 2026-10-03 — V1 P0 context-limit audit: distinguish Storyteller's guard from GPT limits

- A read-only code audit confirmed that the reported “could not fit” error is generated locally before a provider request. At the time of this audit, Storyteller applied the same 24,000 serialized-byte preflight to every configured model ID; the code has no ChatGPT-plan-specific evidence calibrating that number. This error is not evidence that GPT or the Plus usage quota rejected the turn.
- The context compiler already projects relevance before measuring size, trims unrelated history and details, then progressively compacts narration and can omit transcript history. It intentionally retains the current scene, relevant public/private canon, active state, and the saved action. Thus long transcript growth is bounded, but large necessary scene data (including long allowed campaign text or many active records) can still exceed the current bound. Required canon must remain in durable local storage and must not be silently dropped.
- The current HTTP plan-usage route has no persistent ChatGPT-thread memory: every request must include needed context and `previous_response_id` is unsupported. The documented route allows app-handled function/custom tools but not hosted MCP/connectors. A local read-only state function remains an experiment; its schema, result payload, and extra request round trip must be counted against a deterministic retrieval baseline.
- **P0 direction:** ordinary campaign growth must not strand an action at the local preflight. Use a compact scene snapshot, action-relevant retrieval, safe prose compaction, and a validated per-model request envelope. Test synthetic campaigns across locales and multi-session growth for both relevant-fact recall and irrelevant-context omission. A truly oversized active scene needs safe category-specific review and retry, not routine instructions to shorten player notes. Evaluate tool lookup only when matched benchmarks show better total input and acceptable latency, privacy, and correctness.
- No campaign database, provider, or OAuth session was accessed; no live model request was made. Evidence: `config/config.ex`, `Storyteller.GM.ContextBudget`, `Storyteller.Play` request assembly, and OpenAI's [SIWC preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).

## 2026-10-03 — V1 P0 context recovery: diagnose the local size limit

- A true serialized-request overflow now carries only safe numeric sizes for the largest three context sections (including GM instructions) through the failed turn. Fixed category abbreviations and base-36 byte counts fit in the existing bounded `failure_code`; the public projection decodes only whitelisted category names and numbers. Prompt, world, character, and private-state text are never placed in diagnostics.
- Context serialization/compiler exceptions now produce a distinct `context_compilation_failed` code instead of being mislabeled as a campaign-size error.
- The localized recovery card clarifies that no provider request was sent, shows estimated size against the local bound and its largest contributors, and links to the campaign overview and setup editor. The saved action remains visible and retry continues the same turn. Existing account usage-pause behavior remains separate.
- This is diagnostic/review support, not a complete curation flow: canonical world/place/inventory records are not editable from that card. Add a safe category-specific review/edit action before treating truly oversized required state as fully recoverable.
- **Checks:** full WSL suite passed (**464 tests, 0 failures**, max concurrency 8); the context-budget suite passed (**27 tests**), the localized overflow LiveView regression passed (**74 discovered, 1 selected, 0 failures**), the selected Play retry regression passed (**1 test, 0 failures**), and Gettext freshness, formatting, development warnings-as-errors compilation, and `git diff --check` passed. No live model, OAuth, development campaign, or vineyard data was used.

## 2026-10-03 — V1 P0 story pacing: complete the beat before handing control back

- Tightened the GM's adaptive-pace rule: finish the consequences and relevant co-present reactions for an incidental act or line instead of handing control back immediately, unless a player choice is due. Intent still determines whether a moment stays close or moves through a montage.
- Fake-provider tests assert the policy and accept a complete tasting-beat exchange. This protects the intended behavior at the request boundary but cannot prove that live model prose will consistently follow it; matched story play reviews remain necessary.
- **Checks:** WSL play suite passed (**113 tests, 0 failures**); full WSL suite passed (**462 tests, 0 failures**); development warnings-as-errors compile, formatter, and `git diff --check` passed. No live model or campaign data was used.

## 2026-10-03 — V1 P0: project relevant context before the request-size check

- Fixed the normal-path behavior found during the size-error audit. The GM compiler now applies its first-tier relevance projection before checking the 24,000-byte serialized-request bound, instead of sending every campaign section whenever the unprojected request happened to fit.
- A synthetic under-budget regression keeps the current scene, an older Finca/Bodega travel-and-duty fact, active objectives/commitments, and current/adjacent place details. It omits irrelevant older prose, remote profile/place detail, closed-objective prose, and unrelated summary/continuity detail, and records those omissions. Small public character facts remain available; a remote character's full profile and place detail is restored when the action matches that character's stored facts.
- The play layer marks older events selected by its action-and-vantage-aware database query. The compiler uses these internal sequence hints to protect cross-language or indirect scene recall when its separate lexical ranker has no match, strips the hints before model serialization, and still rejects unrelated decoys when a stronger focused match exists. A separate long-campaign regression keeps the named Finca/Bodega fact while excluding same-topic Bodega decoys.
- The fixture's request estimate drops while the source context remains unchanged; the complete campaign record stays durable in the database. The application keeps its bounded recent-history slice and compacts it to 12 recent plus up to 8 relevant older events for the request.
- Existing progressive history compaction and safe over-budget rejection still apply if the projected required state cannot fit. This reduces ordinary-growth failures but does not guarantee that arbitrarily large required canon fits. The lexical relevance ranker can still miss implicit or paraphrased older facts; broader retrieval quality, a player-friendly remedy for genuinely oversized required state, and measurement over varied long-campaign fixtures remain open P0 work.
- Read-only, app-handled function tools remain an experiment for targeted state lookup. Returned facts still consume model input and extra tool rounds may add latency; this is not a substitute for bounded context. The current ChatGPT-plan preview supports app-defined function/custom tools but not hosted MCP/connectors.
- **Checks:** focused ContextBudget/Play/history-recall suites passed (**144 tests, 0 failures**); full WSL suite passed (**462 tests, 0 failures**, max concurrency 8); test/development warnings-as-errors compilation, formatting, Gettext freshness, asset build, and `git diff --check` passed. Automated tests used only `storyteller_test`; no development/QA campaign database, live model, OAuth, or restricted campaign was accessed.

## 2026-10-03 — V1 UI follow-up: keep the play composer reachable

- The user reported that, in Firefox, typing controls could be pushed below the viewport with no way to bring them back. The roomy-desktop media rule locked the document and play `main` column against vertical overflow while only the story history could scroll.
- The play `main` column can now scroll vertically when its content exceeds the locked viewport; the story timeline remains an independent history scroller. A focused LiveView stylesheet regression asserts both scroll regions.
- **Checks:** WSL `mix test test/storyteller_web/live/session_live_layout_test.exs` passed (**1 test, 0 failures**), and `git diff --check` passed. Firefox visual confirmation remains outstanding; this fix did not access the reported campaign or submit a turn.

## 2026-10-03 — V1 P0 refinement: prevent growing campaigns from hitting the context wall

- The owner reports a saved action that could not be sent because required campaign details exceeded Storyteller's local GM request-size bound. The configured default is **24,000 serialized bytes**, not the account/model token limit; an estimated 512-byte framing allowance is used. The current message asks the player to shorten notes, which is too burdensome as routine campaign growth and can stop the story. Treat this as a P0 reliability defect, not normal campaign maintenance.
- The first request build retains broad canonical sections whenever the request still fits. Only after the total exceeds the bound does compaction reduce the timeline and omit remote character/place details, closed objective details, and summaries. Canonical state is protected, but full place descriptions/facts were redundantly embedded in each character's `current_place` as well as the shared places list. The local size estimate measures the encoded context string and may not model all escaping in the outer HTTP request body.
- A pure fictional offline reproduction using individually valid 10,000-character campaign premise and current-place description plus near-limit GM instructions estimated **31,825 bytes** and returned the same context-budget failure. This confirms the error can come from Storyteller's local preflight even when no model/account limit has been reached.
- **Request-path audit:** the 24,000-byte check is computed from serialized instructions, context JSON, and a fixed framing allowance; it is not a token count, account limit, or provider response. One prior offline sample was 24,568 bytes (10,168 instruction bytes, 13,888 context bytes, 512 framing bytes). The UI currently tells the player to shorten instructions or notes even though canonical place/world/character data can be the source. The adapter sends `store: false`, has no tool-call dispatcher/continuation loop, and the current HTTP plan-usage flow cannot reuse `previous_response_id`; the model therefore has no persistent ChatGPT-thread memory to lean on between turns.
- The first request previously kept broad state when it fit, and avoidable duplicate place details were found and removed. The new relevance-first pass now bounds ordinary requests, but unusually large required current canon (including premise, world, present characters, inventory, and active commitments) can still overflow; existing byte metrics expose section totals, but the 31,825-byte fixture did not isolate which serialized section dominates. A true overflow should be diagnosed by category rather than routing every player to campaign-note editing.
- **Implemented first reduction:** character context now carries only the current place ID, name, and visibility; full description/facts appear once in the shared place record. A behavioral regression covers multiple present characters and confirms the place details remain available. This removes avoidable duplication but does not solve every oversized canonical-data case.
- The authenticated ChatGPT-plan route supports app-defined function/custom tools but explicitly excludes hosted MCP/connectors. The current adapter does not implement tools yet. A future read-only, locally executed function-call loop is a candidate—not an assumed win—because returned facts still consume input and each tool round can add latency. Compare it with bounded deterministic app-side retrieval, including tool schemas, full input/result bytes, visibility, provenance, accuracy, and end-to-end time. See [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) and the [plan-usage overview](https://developers.openai.com/siwc/token-sharing-open-source).
- **Still open:** broaden reviewed multilingual and implicit-reference recall; test context growth with a varied set of longer synthetic campaigns; make the recovery path for genuinely oversized required state more helpful; and measure the request-size/latency tradeoff before adding function-call round trips. The current relevance projection and internal retrieval priority are covered by the newer entry above. Use synthetic long-running campaigns and isolated fictional QA/test data only; no development/QA campaign, provider, or OAuth data was used for this audit.

## 2026-10-03 — V1 story-quality iteration 13: grounded ensemble handoff and latency evidence

- In the isolated fictional Quiet Observatory campaign, Rowan inspected chart margins for source credits and dates. The GM described what was legible, preserved the blurred date as unknown, then let Lina explain the shared-source implication and Mira distinguish a catalogue epoch from an observation date. It returned control on a specific next choice without asking Rowan to invent what the charts contained or making another player decision. The response moved game time three minutes and completed in roughly 42 seconds.
- The newly enabled local stage telemetry measured context load/build at 82/94 ms, model resolution at 3.2 s with a cache miss, first output at 10.8 s, full provider stream at 38.1 s, proposal validation at 19 ms, and commit at 8 ms. First-output time is within the provider-stream duration, not an extra interval. This points to provider generation as the largest measured wait in this one sample; it does not establish a general latency distribution or explain every previous slow turn.
- Raised the development logger threshold to `:info` because Phoenix debug logs include LiveView event/session parameters. Safe stage diagnostics remain visible while player text and session values are excluded from the local console.
- **Next:** continue the V1 P0 story-quality comparison across close conversation, sensory scenes, ensemble dialogue, and broad time passage; compare pacing, agency, continuity, and latency against the user's in-chat reference. Keep play-disrupting UI fixes in scope. Do not begin release packaging until story quality is ready.
- **Checks:** WSL full suite passed on rerun (**461 tests, 0 failures**); the isolated LiveView startup scenario also passed (**74 tests in its file, 0 failures**). Development/test warnings-as-errors compilation, formatting, Gettext freshness, asset build, and `git diff --check` passed. One connected fictional sample is evidence, not a quality or latency sign-off.

## 2026-10-03 — V1 story-quality iteration 12: complete scene beats and diagnose slow turns

- Rephrased the runtime NPC handoff rule: a directly addressed character gives one cohesive answer; another present character can add a distinct reaction only when it completes the same beat. The GM yields at a genuine choice and does not make every character speak. Removed duplicated prompt text to keep the serialized instruction below the 11 KB guard. A fake-provider regression checks the rule reaches the request and that a two-character scene can persist; this does not prove live model compliance.
- Added a supervised, local telemetry reporter for context loading/building, OAuth access-token retrieval, model resolution and catalog-cache hit/miss, request-to-first-output, full provider stream, proposal decode/validation, and commit. It logs only fixed stage/cache labels, elapsed milliseconds, and success/failure. It does not log campaign content, prompts, outputs, account identifiers, or tokens.
- **Checks:** WSL full suite passed (**461 tests, 0 failures**); test/development warnings-as-errors compilation, formatting, Gettext freshness, asset build, and `git diff --check` passed. The generated POT source references were refreshed.
- **Limit:** The new timings make the next isolated player-triggered turn diagnosable; they do not yet explain or reduce the recorded 71-second response. No provider request was made.

## 2026-10-03 — V1 story-quality iteration 11: own the tasting, leave the reaction to the player

- Tightened the GM contract for wine, food, and drink tastings: give a concise, vivid profile of relevant observable qualities first; use a qualified judgment from an established, relevant expert who is actually present; then leave the player's subjective response open. The GM must not ask the player to invent the item's sensory properties or dictate the character's opinion, feelings, words, or next action. Unsupported causes and comparisons remain uncertain. The sequence is explicitly limited to tastings so ordinary scenes are not forced into it.
- Extended the fake-provider play test with two present specialists and distinct areas of expertise. It verifies their expertise reaches the GM request and that the provider instructions set the sensory-fact, expert-judgment, and player-agency order. This checks request construction and campaign context, not live prose quality.
- **Checks:** focused sensory/context regressions passed; full WSL suite **457 tests, 0 failures**; test and dev warnings-as-errors compilation, formatting, and `git diff --check` passed. The sensory request remains unverified with a live model; no provider request was made.

## 2026-10-03 — V1 UI iteration: give tracked-resource groups their full width

- Reproduced the resource-copy squeeze on the isolated port-4003 visual QA campaign using four temporary synthetic public fields. The nested two-column grids placed each panel section in half the resource card; rows measured about **80 px** wide and the long values grew up to **327 px** tall. Each section now spans the full ledger width; the same rows measure about **171 px**, and their height fell to **109–171 px**.
- Added a LiveView regression assertion that each panel section spans the full grid width. The temporary fields were removed and the isolated QA campaign restored to its prior state; no story events changed. This used no live model request and did not open campaign 37/38 or the Vineyard.
- **Checks:** focused WSL LiveView test passed (**1 test, 0 failures**); `MIX_ENV=dev mix assets.build` emitted the Tailwind span utility; full WSL suite **457 tests, 0 failures**. The viewport showed only part of the full card at 720 px, so long-board scrolling and complete visual review remain open.

## 2026-10-03 — V1 story-quality iteration 10: remove repeated model-catalog lookup

- The connected Automatic model preference caused a serial `/v1/models` lookup on every GM turn before `/v1/responses`. The OpenAI adapter now caches a successful, nonempty model list in memory for up to five minutes, keyed by the stable OAuth account subject. The cache holds at most 16 accounts, expires entries, and stores no access tokens, email addresses, prompts, or campaign data. The account-settings page and model-save validation still fetch a fresh catalog; failures are never cached.
- A synthetic Quiet Observatory ensemble action produced a grounded two-person exchange: coastal surveyor Lina described evidence of a shared chart source, and Mira added a distinct caution about publication dates versus observation dates. It avoided repeating the whole investigation or taking the player's choice. The completed turn took **71 seconds** in Automatic mode; first text was visible by the 10-second progress check. This is a single sample, not a latency benchmark. The catalog cache removes one avoidable request but has not been retested with another live provider turn, so the large remaining latency is still a V1 P0 issue.
- **Checks:** focused OAuth/provider/cache tests passed (**52 tests, 0 failures**); full WSL suite passed (**457 tests, 0 failures**); test/dev warnings-as-errors compilation, format check, and `git diff --check` passed. No additional provider request was made after implementing the cache.

## 2026-10-03 — QA follow-up: prevent ambiguous duplicate-place placement

- Manual QA in the fictional Quiet Observatory campaign found two public place records with identical names and details. The campaign editor showed them as indistinguishable choices; selecting the legacy duplicate put a new character at a different canonical place ID, so the character roster showed the same place name while “Here with you” correctly omitted them.
- The new-character place selector now collapses only records with identical public names, descriptions, and facts. It prefers the player's current place, then the place with the most characters, and then a stable non-initial ID. Existing place records and prior character locations remain untouched.
- Added LiveView behavioral coverage that seeds an indistinguishable duplicate, verifies it is not offered as a second choice, and confirms the newly placed character uses the chosen canonical place. This closes the observed editor ambiguity. A live natural introduction was sampled in V1 story-quality iteration 9 below.
- **Checks:** campaign-authoring LiveView tests passed (**20 tests, 0 failures**); full WSL suite passed (**454 tests, 0 failures**); dev/test warnings-as-errors compilation, formatting, Gettext freshness, and `git diff --check` passed. Only the isolated QA campaign/server was changed; port 4000 was not touched.

## 2026-10-03 — V1 story-quality iteration 9: a new character takes the floor naturally

- After placing Lina Morcant in the canonical observatory room through the corrected editor, the live player board showed her under “Here with you.” One connected action asked the unfamiliar surveyor who she was and what brought her to the observatory.
- The GM introduced her in one short scene beat with a physical cue and then gave Lina one concise answer: her name, coastal-survey work, temporary lodging, and a relevant question about the charts. The result used narration and a character speech bubble; it added no system-style character notice, unrelated facts, roll, or player choice. The world clock stayed at Late Autumn, Day 31, 06:00.
- The turn completed between the 10-second and 20-second follow-up observations. This is one positive natural-introduction sample, not a latency guarantee or story-quality parity result. Story depth, flexible social/tense-scene pacing, and repeated voice distinction remain V1 P0.
- The old synthetic QA NPC Talla remains attached to the legacy duplicate place record; existing records were not silently rewritten. The resource-panel overlap and compact-board viewport issues also remain open UI work.

## 2026-10-03 — Functional MVP accepted; V1 P0 story QA is active

- The functional MVP QA gate is now accepted. The criteria remain regression checks; V1 work is led by story quality, with play-disrupting UI issues alongside it. Open-source clone/run and secret-handling preparation stays deferred until play quality is ready.
- A controlled Quiet Observatory replay covered two nights in one player turn. Mira completed the requested repeat comparison from Day 29 at 18:23 through Day 31 at 06:00, summarizing repeated checks as one scene beat and one reply. The mismatch persisted; the GM preserved uncertainty, proposed a useful next investigation, and did not invent player action, a roll, or a premature question. The turn completed between the 12-second pending and 27-second follow-up checks; exact latency was not instrumented.
- A GM-only voice profile for Mira survived leaving and reopening campaign setup. A technical question drew practical astronomy language but no visible mannerism; a light joke then elicited one brief half-smile cue and a dry, character-specific reply without inventing chart evidence. The voice profile can shape a fitting beat, but consistent distinction across characters remains unproven. These two responses completed within 12–24 and 24–36 second observation windows respectively; collect provider telemetry before treating these as exact latency measurements.
- A synthetic second character, Ivo Maren, was added to the Quiet Observatory QA campaign and placed in the observing room with a short, practical voice profile. One player action got both him and Mira to answer in separate speech bubbles: Ivo focused on the lens housing; Mira proposed tracing chart sources and distinguished what that could and could not establish. They stayed within known facts and left the choice to the player. Ivo's first story appearance lacked a natural narrative introduction; the GM request now carries a derived first-appearance signal based on full public history. Fake-provider regressions cover a setup NPC's brief public introduction and prevent re-introducing an established NPC after their first mention ages out of the retained excerpt. A live new-character introduction remains to be sampled.
- A follow-up action hit Storyteller's local 24 KB serialized-request ceiling before any provider request; it was saved and Retry remained available. The last-resort compactor now omits the transcript only from that request after shorter history tiers fail, retaining current canon, present characters and voice profiles, compact memory, relevant continuity, and the player action. The omitted-history flag directs the GM to rely on those sources and not invent missing events; full history remains durable. Retrying the exact saved action on port 4003 completed, producing one reply from Mira and one from Ivo; both kept their distinct practical voices, and game time remained Late Autumn, Day 31, 06:00. Completion appeared about 27 seconds after the pending state was first observed (not instrumented). This is one confirmed overflow recovery, not a latency guarantee.
- Tightened the GM contract so each speaker's saved profile shapes dialogue without blending, mannerisms appear only when apt, quirks stay relevant, and humor/gestures are not forced or repeated. Provider-boundary and compact-context behavioral checks cover the contract; the prompt remains under the existing 11 KB guard.
- Record this as one adaptive-pacing pass only. Follow with close dialogue, spontaneous scene details, and voice consistency. The resource overlap remains unconfirmed; CSS review found the desktop two-column panel nesting can shrink rows to about 80px when multiple panel groups exist, so reproduce and improve readability using isolated fixture data.
- **Checks:** WSL full suite passed (**453 tests, 0 failures**); dev/test warnings-as-errors compilation, formatting, Gettext freshness, and asset build passed; JavaScript tests passed (**14 tests, 0 failures**); `git diff --check` passed. Elixir checks ran in WSL; the standalone JavaScript tests used the host Node runtime because Node is not installed in WSL.

## 2026-10-03 — V1 P0: complete bounded delegated work

- Compressed the adaptive pacing rules while clarifying that a capable, present NPC should finish a bounded task the player delegates and return at a genuine decision. The GM should ask only about real blockers, state knowledge/access/time limits, and never invent success or the player's follow-through.
- Added a fake-provider behavioral regression that checks the delegated task guidance, a useful supported NPC result, and a clean handoff without a forced player question or roll. The GM instruction bundle remains under the existing 11 KB guard.
- In connected Quiet Observatory QA, a direct Ask GM question about whether Mira's chart comparison ruled out a shared omission received a concise uncertainty-aware answer with a next investigative step; the visible clock stayed at 18:15. A follow-up bounded task had Mira inspect both charts' coverage and markings; she returned a supported finding in eight in-world minutes, with a narration and one NPC reply, then handed control back. The clock advanced to 18:23. This verifies the new handoff behavior in one sample, not story-quality parity; response time remained around 20–30 seconds.
- Synthetic resource-board visual review did not reproduce text overlap in the first visible rows, but found the side rail cramped and longer resource lists below the 720 px viewport. Keep the layout issue in V1 UI work and reproduce only with isolated fixture data.
- **Checks:** WSL full suite passed (**450 tests, 0 failures**); dev/test warnings-as-errors compilation, formatting, Gettext freshness, assets build, and `git diff --check` passed. All connected checks used only the fictional QA database; no source campaign or comparison conversation was opened.

## 2026-10-03 — V1 P0: turn canon rejection into a playable discovery

- The isolated Quiet Observatory replay's safe failure tag was `invalid_entry_fields`. The saved action and world remained unchanged; no part of the rejected proposal had been committed. The compact continuity shape named fields but not allowed values or text bounds, so the GM contract now gives the accepted kind/visibility values and title/detail lengths without exceeding the existing prompt-size regression limit.
- On the next retry of that same saved action, Mira compared the two open charts with the visible sky over fifteen in-world minutes. The GM supplied a concrete local mismatch, Mira gave a qualified expert conclusion, and Rowan did not have to invent the chart reading. The scene panel updated and the public fact was saved with event provenance. The turn completed on attempt seven; end-to-end response time was about 35 seconds.
- This is evidence that the state contract can carry a player-facing discovery, not story-quality parity. The earlier scene still spent too many turns circling the comparison, and this response remains slow. Continue to measure time-to-decision, useful scene progress, and response latency on separate fictional beats.
- **Checks:** focused prompt behavior passed; WSL full suite passed (**449 tests, 0 failures**); test/dev warnings-as-errors compilation, formatting, Gettext freshness, asset build, and `git diff --check` passed. Connected testing used only `storyteller_mvp_qa_20261003` on port 4003. Port 4000 and the source/Vineyard campaign were not accessed.

## 2026-10-03 — V1 P0: grounded discoveries and expert agency

- With functional QA accepted as the MVP baseline, story quality is the active P0. Tightened GM guidance so the GM supplies ordinary sensory facts and an expert NPC's qualified judgment, keeps prompt/canon-check reasoning out of narration, and can establish a witnessed clue on a known present object without inventing its cause. Continuity operations now have a compact exact shape; action pacing retains montage guidance and skips routine steps.
- Added behavior coverage for an earned clue with public event provenance, transient scene texture staying out of the continuity ledger, and secret-safe structural rejection logging. Invalid continuity proposals still fail closed; safe reason tags now explain the shape/rule failure without logging proposal contents.
- On the refreshed isolated Quiet Observatory QA build at port 4003, the saved observation request still failed at continuity-change validation. The action remains retryable and no GM narration or campaign changes were saved. This is an open story/state integration defect, not a quality pass. The previous build had shown public “GM clarification” text; this updated retry did not return a usable response, so the changed narration guidance is not yet confirmed live.
- **Checks:** WSL full suite passed (**449 tests, 0 failures**); dev/test warnings-as-errors compilation, formatting, Gettext freshness, asset build, and `git diff --check` passed. QA used only `storyteller_mvp_qa_20261003`; the primary port 4000 server and source campaign were untouched.

## 2026-10-03 — Isolated local QA runtime and bounded connected replay

- Development config now accepts `STORYTELLER_DB_NAME` and `PORT`, keeping the default `storyteller_dev` / 4000 behavior and loopback binding while allowing a durable manual-QA database on another local port. The Windows/WSL command sequence is documented in `docs/LOCAL_DEVELOPMENT.md`; stale campaign IDs were removed from the live-testing instructions.
- Historical first replay: four bounded attempts did not produce an opening scene; the first two were safely rejected (`proposal_rules`), the third identified character creation, and the retry after clarifying its schema ended with a generic provider error. Later connected QA and the functional MVP pass are recorded below; this first replay was not the final sign-off.
- **Checks:** the isolated database is migrated and seeded, and its Phoenix server ran on loopback port 4003. Full ExUnit passed (**439 tests, 0 failures**); warnings-as-errors compilation, format, `git diff --check`, and Gettext freshness passed in WSL. The evidence and exact boundary are in `docs/UX_ACCEPTANCE.md`. The primary 4000 server, campaign 37, the Vineyard campaign, and its source ChatGPT thread were not opened or changed.

## 2026-10-03 — Tighten opening guidance and rejection diagnosis

- Opening scenes now explicitly avoid D20 requests, and the response contract spells out the required NPC creation fields. Fake-provider tests verify the guidance and reject a premature opening roll without writing timeline state. Connected replay still has not confirmed this as a fix.
- Refined internal allow-listed failure categories by proposal field/scope so safe rejection metadata can identify which validator needs review without retaining raw model output or exposing categories to players.
- **Checks:** focused and full fake-provider suites passed. Manual connected replay remains unresolved as recorded above.

## 2026-10-03 — Preserve in-flight recovery state across usage-status changes

- Added an isolated fake-provider regression for an account-usage status changing to paused or unavailable while a post-roll response is resolving, followed by a generic provider failure. A fresh LiveView restores the saved action and D20 result, shows only the matching status, keeps retry disabled while requests are blocked, and makes no automatic retry.
- The regression found no product defect; existing recovery handling passed for both status outcomes.
- **Checks:** four focused SessionLive recovery tests passed (**4 tests, 0 failures**); test-environment `mix compile --warnings-as-errors`, focused format check, and `git diff --check` passed in WSL. No live provider or development database was used.

## 2026-10-03 — Compact the play board and retain safe rejection diagnosis

- Reordered the desktop player board for the current scene, tracked resources, player character, and inventory; campaign memory/objectives and correction/roster records now open on demand. A LiveView regression covers the controls. Loaded an isolated fictional fixture from the separate `storyteller_visual_qa_20261003` database at port 4003. The rendered board contains the expected play information, but viewport scroll metrics were unavailable, so a 1280×720 and narrow-screen visual pass remains open before the no-second-scroll goal can be marked complete.
- Persisted only the six existing allow-listed proposal-validation categories on failed turns, with a database constraint tying them to `invalid_response` at `proposal_validation`. Retrying clears the old category. Public turn projections continue to exclude it; no prompt or model text is stored.
- **Checks:** full WSL suite **438 tests, 0 failures**; JS **14 tests, 0 failures**; development/test warnings-as-errors compilation, formatter, Gettext extraction check, and asset build passed. The shared development database's sole pending additive migration was applied without touching campaign rows. The visual fixture used its own database and no retry or OAuth consent was used. MVP functional sign-off remains open.

## 2026-10-02 — Recheck connected time-passage recovery

- In the separate Quiet Observatory QA session, one owner-authorized retry of the saved “A day passes” turn stayed in progress for about 20 seconds and ended with a safe-rejection message. The player input remained visible, and the world state and story did not change. The connected account was not shown as paused during this attempt.
- Read-only metadata records `invalid_response` at `proposal_validation`, but the specific allow-listed rejection category is not persisted and no server terminal was attached. The exact rule failure remains unknown. No further live retry was sent on the same turn.
- At 1280×720, the outer document fits the viewport, but the story reader and right player board scroll separately. The board has 810px of content in a 434px viewport; this is a visible gap against the goal that play-state panels remain available without their own scroll.
- **QA boundary:** no campaign state was edited manually and no data was imported.

## 2026-10-02 — Keep account usage recovery truthful during status outages

- Replaced the ambiguous boolean usage check with `available`, `paused`, and `unavailable` states. If local status storage temporarily fails, Storyteller holds provider requests and tells the player it cannot check status; it does not claim ChatGPT reported a limit or offer the account-resume action. A local Check again control restores the appropriate state without making a provider request.
- The saved turn, player input, roll result, and campaign canon remain unchanged. Submit, retry, roll, and automatic resolution stay fail-closed until status is confirmed. Copy and recovery behavior are covered in English, Spanish, and French.
- **Checks:** focused fake-provider recovery tests **4 passed, 0 failures**; `mix format --check-formatted`, `mix gettext.extract --check-up-to-date`, `mix compile --warnings-as-errors`, and `git diff --check` passed. Full-suite result is recorded in the current QA checkpoint after rerun. No live provider request or campaign access was made.

## 2026-10-02 — Record the live QA usage-limit outcome

- One controlled Retry of the saved “A day passes” turn in the separate Quiet Observatory QA campaign returned an account usage-limit notice. The input stayed saved; the game date, time, weather, location, and story did not change.
- After the request settled, the turn showed a generic provider failure and the usage-limit pause banner was no longer visible. No further live retry was sent while account usage was limited. This does not pass the connected time-passage QA gate; the limit-to-final-error transition needs investigation before sign-off.
- The protected campaign 37 and the Vineyard campaign were not opened. The QA session remains available with its saved turn for later diagnosis.

## 2026-10-02 — Keep dense tracked-resource ledgers readable

- Added bounded wrapping to resource labels, units, and values so long unbroken text cannot widen the play sidebar or run into adjacent ledger rows.
- Added an isolated LiveView stress regression with 18 resource rows, long labels and units, and a 406-character unbroken value. It verifies every value remains inside its own labeled row. This does not count as visual reproduction of the owner's reported overlap; the protected comparison campaign was not opened.
- A campaign-editor test redirected unexpectedly in one earlier full run. The exact test and whole module passed in isolation; two later full-suite runs (including a different seed) both passed. The failure has not reproduced.
- **Checks in WSL:** focused resource LiveView test **1 passed**; campaign-authoring LiveView module **19 tests, 0 failures**; two full-suite runs **434 tests, 0 failures each**; JavaScript **14 tests, 0 failures**; test/dev warnings-as-errors compilation, format check, Gettext freshness, asset build, and `git diff --check` passed. The MVP live-turn and independent visual QA gates remain open.

## 2026-10-02 — Diagnose rejected GM proposals without retaining their content

- Validation failures now emit a finite reason category in local warnings: proposal shape, time advance, player agency, location/presence, private-fact boundary, or other proposal rules. The player's recovery message stays generic; no prompt, provider output, or campaign facts enter the log.
- Added a fake-provider regression for invalid time advance and player-authored dialogue during time passage. It confirms the safe categories, absence of generated text in logs, an unchanged world clock, and no timeline events. Movement/presence and privacy rejection paths also receive their own categories.
- One further authorized retry of the saved “A day passes” request in the fictional Quiet Observatory campaign failed again at `proposal_validation`; its input remains saved and the world date, time, weather, and location remain unchanged. The historical model output was not retained, so its exact rejection cannot be recovered; categories will make future failures diagnosable.
- **Checks:** full WSL suite **433 tests, 0 failures**; JavaScript **14 tests, 0 failures**; test and dev warnings-as-errors compilation, formatter, Gettext freshness, asset build, and `git diff --check` passed.

## 2026-10-02 — Set the MVP exit and V1.0 story-quality bar

- Confirmed the release sequence: finish functional QA before calling the product MVP; then make compelling, flexible, coherent story the V1 P0, with play-blocking UI defects fixed alongside it.
- Deferred open-source clone/run readiness and the repository secret/private-data audit until the owner considers the play experience polished. V1.0 ships only after the story-quality bar and release preparation are complete.
- A read-only audit found no mount/reconnect/poll/recovery path that creates a new time-passage turn. Its creation requires the submitted form event; the historical turn lacks tab/event attribution, so its exact source cannot be recovered. Repeated retries of the fictional Quiet Observatory time-passage input ended with another `invalid_response` at `proposal_validation`; time and canon did not change, and the input remains saved. Safe local validation categories are now logged for future failures; this historical response is unavailable for exact diagnosis, and the QA gate remains open.
- A read-only 1280×720 QA check found that the full recovery card collapsed the story scroller and pushed part of the composer below the viewport. Made the failed-turn card compact, removed its duplicate generic saved-action callout, and placed common nudges alongside the interaction modes. After the change, the independently scrollable story viewport grew from 39px to 116px; the latest saved action, Retry button, composer, and both nudges are visible together.
- **QA still open:** finish the remaining functional pass on independent fictional data, including a connected time-passage turn that completes, an ordinary action that completes, and an independent visual reproduction of the reported tracked-resource overlap. Do not use the Vineyard source or imported comparison campaign; reproduce reported UI defects only in a clean fictional fixture.
- **Checks:** focused SessionLive **69 tests, 0 failures**; full isolated suite **432 tests, 0 failures**; JavaScript **14 tests, 0 failures**; WSL test/dev warnings-as-errors compilation, formatter, asset build, and Gettext extraction/merge freshness passed. One user-authorized retry used the connected model in the fictional QA campaign; no Vineyard data was accessed.

## 2026-10-02 — Make failed-turn recovery quieter

- The failed-turn panel repeated the saved-action/retry explanation beneath an error that already said the action was preserved. Removed the duplicate generic retry paragraph; the error cause, saved action in the story, contextual route advice when relevant, and Retry button remain. The after-roll state still names the saved D20 result so a player knows it will be reused.
- Updated LiveView assertions to verify the failure and saved action are visible, retry remains explicit, and the redundant copy is gone. A read-only check in the separate Quiet Observatory session confirmed the concise state renders; no retry or provider call was made.
- Tightened the manual QA boundary to use independently authored fictional campaigns and high-level pacing feedback; do not access, import, or test against the Vineyard source or an imported comparison campaign.
- **Checks in WSL:** focused SessionLive **69 tests, 0 failures**; full suite **432 tests, 0 failures**; test/dev warnings-as-errors compilation, formatter, Gettext extraction, and `git diff --check` passed. No live model call was made.

## 2026-10-02 — Carry the GM through the immediate scene beat

- Tightened the adaptive-pace rule: the GM describes observable outcomes and consequences, includes grounded reactions or replies from present characters when they naturally complete the beat, and returns control at the first decision owned by the player. This targets one-line NPC handoffs without forcing every character to speak or authoring the player's follow-through.
- Added a fake-provider `Play.submit_turn` behavior test that sends this guidance in an action request and persists sensory narration plus two relevant NPC replies in the same turn. This verifies request construction and the event path, not the quality of prose produced by a live model.
- Updated the campaign-independent GM policy to match the request policy. Matched acceptance criteria already exist in `docs/UX_ACCEPTANCE.md` for external sensory authority, flexible pacing, and a natural player handoff.
- **Checks in WSL:** focused `PlayTest` **100 tests, 0 failures**; full suite **432 tests, 0 failures**; test/dev warnings-as-errors compilation, formatter, Gettext extraction, and `git diff --check` passed. The new regression uses a fake provider and fictional test fixtures; no live model call or development campaign was used.

## 2026-10-02 — Keep session recovery scoped and the MVP QA gate honest

- Corrected the QA conclusion: the earlier statement that the functional MVP gate had passed was premature. Core time-passage, retry, reload, and cross-session recall paths have live evidence in the separate Quiet Observatory campaign, but sign-off remains open.
- During the reload/layout QA window, an unrequested failed turn with player text “A day passes” appeared in a later session. It changed no canonical state and was not retried; its origin is unknown. A review of an earlier session showed that the campaign-wide current-turn lookup leaked that later session's failure and pending text into the earlier session.
- Scoped `public_current_turn` presentation to the session being viewed and added a LiveView regression proving that a later failed turn does not show its error or pending action in an earlier session. The underlying campaign-wide turn lookup remains in the submit/recovery flow; only the review screen projection is session-scoped.
- Added an assertion that opening a failed same-session turn preserves its saved input and failed status without incrementing its attempt count, so loading the screen does not silently retry it.
- Kept the compact 700–799px desktop layout: at 1280×720 it retains a fixed-height board and a readable story viewport after compressing secondary chrome. This was visually measured in the separate fictional QA session; it does not close the functional MVP gate.
- Remaining MVP QA includes investigating the unexplained submission path and finishing the unverified functional checks without opening or mutating the vineyard campaign. V1 P0 remains story quality and play-disrupting UI issues; open-source clone/run and secret-handling preparation follows once the game is polished enough for 1.0.
- **Checks in WSL:** focused SessionLive suite **69 tests, 0 failures**; full suite **431 tests, 0 failures**; test and dev warnings-as-errors compilation, formatter, Gettext extraction freshness, and `git diff --check` passed. The test suite uses fake providers; no live model call was made during this verification.

## 2026-10-02 — Set the functional MVP exit and V1 P0

- The owner clarified the product sequence: finish QA of basic campaign play and persistence, then call the functional baseline the MVP. MVP qualification does not claim story-quality parity with ChatGPT.
- V1's P0 is compelling, responsive GM storytelling: flexible pace, engaging scenes, clear sensory/world facts, distinct character voices, smooth handoffs, continuity, and tolerable latency. UI defects that interfere with play remain in V1 scope; open-source clone/run instructions and secret/private-data review follow once play quality is ready.
- Updated `IMPLEMENTATION_PLAN.md` with the functional exit checks, remaining MVP gates, and measurable V1 story scenarios. Updated `docs/UX_ACCEPTANCE.md` to distinguish functional acceptance from literary quality.
- In the separate fictional Quiet Observatory campaign, one simple Ask about current weather completed through the configured ChatGPT-plan connection in about 12 seconds. Its narration persisted after reload while date, time, weather, and location stayed unchanged. This verifies the basic Ask path only, not stateful movement or prose quality.
- The earlier movement-and-inventory action and its retry both failed proposal validation; no canon was applied. Read-only QA confirmed that the fictional campaign had no modeled travel connections, so the attempted NPC move had no canonical route. The request was invalid under the movement rules. At the time, the player received only the generic `invalid_response` category; the current play screen now adds conditional route guidance after this validation stage. A later weather Ask completed and superseded that failed turn. The imported comparison campaign and Vineyard source were not accessed or changed.

## 2026-10-02 — Make route rejection easier to recover from

- Kept the persisted `invalid_response` and `proposal_validation` classification unchanged, while adding a conditional movement-route hint to that failure state. It explains that a route may be established in the same response and then retried, without surfacing character names, private campaign details, or raw validator output. Added Spanish and French translations.
- Added a LiveView behavior test for disconnected movement rejection, preserved canon and timeline, safe error content, and separation from decode failures; the existing same-response route test still passes. Added locale rendering coverage.
- Refined the release roadmap: functional QA is the MVP gate; V1 P0 is story quality and disruptive UI fixes; clone/run and secret/private-data release preparation follows once the game is polished.
- **Checked in WSL:** full suite **429 tests, 0 failures**; warnings-as-errors compilation, formatter, Gettext freshness, and `git diff --check` passed. No live-model call or campaign mutation was made; automated tests used the isolated test database. A live stateful turn remains a required MVP sign-off check.

## 2026-10-02 — Confirm the functional MVP loop across sessions

- In the separate Quiet Observatory QA campaign, the first live “advance ten minutes” response failed proposal validation without changing canon. Retrying the same saved turn succeeded: server-tracked elapsed time advanced exactly ten minutes, the character stayed in the guest room, and the canonical weather fields stayed unchanged. The story and clock persisted after reload.
- Started a later session and confirmed the board retained the clock, place, and earlier campaign story. A live Ask about Mira failed proposal validation on its first attempt; retry correctly recalled her current corridor location and that she was waiting to take Rowan to the kitchen for sherry and oatcakes before comparing charts. The completed question and state persisted after reload.
- The LiveView route hint is now limited to action turns, so an unrelated time-passage or question validation failure does not show movement advice. A behavior test covers that distinction.
- **Initial conclusion superseded:** at the time, the available stateful and cross-session observations were treated as passing the functional gate. Subsequent QA found an unexplained failed submission and a cross-session error/pending-action leak; the gate is now explicitly open in `docs/UX_ACCEPTANCE.md`. This was not a V1 story-quality claim. The two live turns both needed a retry, so first-try reliability, adaptive pacing, and comparison with the in-chat reference remain V1 P0. The imported comparison campaign's resource-panel rendering was not inspected.
- **Checked in WSL:** full suite **430 tests, 0 failures**; warnings-as-errors compilation, formatter, Gettext freshness, and `git diff --check` passed. No Vineyard content was read or changed.

## 2026-10-02 — Keep the GM inventory view within the local context budget

- A maximum-size synthetic campaign exposed an avoidable context overflow: public and GM-private inventory arrays were copied into the world maps and serialized a second time in the dedicated inventory section. The local 24,000-byte preflight rejected a request whose serialized context was about 225 KB before projection.
- Removed those duplicate arrays from `world.public` and `world.gm_private`. The complete inventory remains in durable campaign state and the dedicated section; all proposed inventory changes continue to validate against the full canonical ledger.
- For the GM request, keep all item identities when a visibility list has at most 16 items. Larger lists include up to 10 action-relevant identities plus six recent identities. Full description/property data is limited to the strongest match in each visibility list, with bounded text/property size. `context_completeness` marks omitted item rows and details; the GM is instructed not to treat omissions as absence or invent omitted facts. The player-facing inventory remains complete.
- Added a pure context-budget regression and a production `Play.submit_turn` fake-provider regression at the full 200-item combined inventory limit. They verify a specifically named item retains its details, private inventory stays in its private section, redundant world copies are absent, the request stays within the 24,000-byte application bound, and the full saved inventory is unchanged after the turn.
- The 200-item scenario is synthetic and does not establish the cause of the earlier overflow on the imported comparison campaign, which was not accessed. No live model request was made.
- **Checks:** context-budget suite and the focused production request passed; full WSL suite **427 tests, 0 failures**.

## 2026-10-02 — Keep tracked-resource markup from preserving template whitespace

- A separate synthetic resource fixture exposed large gaps and indentation in the live resource card: `whitespace-pre-wrap` was applied to a definition container that also held the correction link and nested receipt. The fixture did not reproduce text overlap exactly, and the imported comparison campaign was not opened.
- Limited preserved line breaks to a value-only span in the live board and campaign detail card. Long typed values still wrap, while labels, values, and correction controls now flow without template indentation.
- Added a rendered regression for long resource values, the value-only whitespace scope, and GM-private field omission. Manually checked the narrow play board with quantity, money, and long text values; values aligned cleanly and controls sat directly below them. Removed all four temporary QA fields afterward.
- **Checks:** three focused `SessionLive` regressions passed; full WSL suite passed (**425 tests, 0 failures**); formatting and warnings-as-errors test/dev compilation passed; Gettext extraction is current. One unrelated flaky assertion surfaced during a broader targeted run: it searched the whole LiveView HTML for `UTC`, which can match the opaque LiveView session token. Changed it to inspect visible game-time labels instead.

## 2026-10-02 — Finish the scene beat before handing control back

- A close reading of the shared campaign confirmed that its rhythm shifts with intent: broad intervals get a selective montage, inspections and choices stay close, and ensemble scenes can include grounded sensory facts and character reactions before the next player decision. Storyteller's compared tasting beat stopped after a short narration and one NPC question, and asked the player to supply sensory information.
- Updated the shared GM policy to keep an in-character exchange moving to its natural handoff, while retaining scoped time-passage montages and the player's control of their own response. The tasting instruction now asks the GM to establish concrete sensory facts at the depth warranted. A fake-provider regression verifies this guidance reaches action requests; it does not claim to test generated prose.
- A first, more verbose action-only prompt exceeded the existing 11 KB instruction-size regression. Removed duplicated guidance and kept the final policy under that guard, preserving the bounded request budget.
- Added a LiveView regression for oversized local context: the saved action and retry remain available in English, Spanish, and French; the provider is not called while the test-only size cap is exceeded; retry completes the same saved turn once the cap is restored. Added a catalog guard that checks all active Spanish/French singular and plural translations.
- **Checks:** focused pacing, time-passage, local-retry, and locale-catalog tests passed; full isolated suite passed (**425 tests, 0 failures**). Formatting, test/dev warnings-as-errors compilation, Gettext freshness, and `git diff --check` passed in WSL. Tests use fictional fixtures and fake providers. A separate owner-authorized live QA action and same-turn retry both failed proposal validation after tens of seconds; the saved action remained retryable and no response or world changes were committed. The request involved an NPC moving between two public rooms with no modeled route; this may explain the failure but is unconfirmed because detailed validation reasons are not retained. Actual pace quality remains unverified; diagnose validation before another live comparison. No OAuth consent was completed.

## 2026-10-02 — Let scene pace follow the player's intent

- Reviewed the owner's shared campaign as a pacing reference. Its routine vineyard work advances over days in broad strokes, while a tasting or live social exchange can stay close to the conversation. The desired quality is that shift in rhythm, not a universal response length. No transcript or plot-specific state was copied into the repository.
- The GM prompt no longer asks for one concise beat or at most one utterance per character per turn. It now distinguishes focused choice/dialogue beats from clearly scoped ongoing work and explicit time passage, while keeping player actions and follow-through under player control.
- Explicit time passage now instructs the GM to resolve routine developments together rather than stopping after each incidental action. Canonical time validation remains in place.
- Refined the pacing language to match the interval's natural scale and removed the general "stay brief" constraint that could undercut a useful workday montage.
- Added production-request assertions for adaptive pace and the interval montage guidance. Automated provider behavior remains a fake-provider boundary check; live prose pacing still needs the owner to review in play.
- **Checks:** full suite (**421 tests, 0 failures**), test/dev warnings-as-errors compilation, format check, Gettext freshness check, and asset build passed in WSL. No live model request was made.

## 2026-10-02 — Localize the time-passage wait nudge

- The contextual wait action had untranslated copy in Spanish and French even though the main time-passage controls were localized.
- Added natural Spanish and French text for both the location-aware and location-free wait instructions. Extended the LiveView regression to activate the nudge in English, Spanish, and French and assert the resulting player draft includes the correctly interpolated place.
- **Checks:** targeted time-passage and pacing tests passed (**2 tests, 0 failures**); full suite passed (**421 tests, 0 failures**); test/dev warnings-as-errors compilation, format check, and Gettext freshness check passed in WSL. The localization assertion reads only isolated fake-provider LiveView fixtures.

## 2026-10-02 — Recover modest GM context overflows without dropping canon

- A read-only diagnostic of the saved failed turn showed a local preflight rejection, not a provider or ChatGPT-plan usage error. The compacted prompt was 24,568 serialized bytes against Storyteller's configured 24,000-byte ceiling: 10,168 instruction bytes plus 13,888 context JSON bytes and 512 bytes of framing. No model request or retry was made.
- The failure exposed a gap in the first compaction pass: it bounded each recent narration to 1,600 characters but did not shrink short-campaign history further when campaign setup and canon left the request a few hundred bytes over budget.
- Added a progressive fallback that first shortens narration older than the newest four events, then shortens the newest events only if needed. Canonical state and private facts remain untouched; the complete event history remains saved locally and the model receives a completeness marker. The compiler option/configuration and telemetry now say bytes explicitly, and the player-facing failure notice identifies a local request-size limit and confirms the failed request was not sent.
- Added an isolated context-compiler regression with a long recent transcript and production GM instructions. It verifies the request reaches the fake provider's boundary within the configured byte bound, all 12 event identities remain available, the newest four receive more context than older narration, and canonical state plus GM-private facts remain unchanged.
- **Checks:** context/play/LiveView tests and the full suite passed (**421 tests, 0 failures**); warnings-as-errors compilation, format check, and dev asset build passed in WSL. Tests use `storyteller_test` with synthetic context and fake providers; no local comparison campaign or live model call is used as an automated test.

## 2026-10-02 — Refresh the comparative design evidence

- Added an October 2 review of first-party product sources for Friends & Fables, Kanka, and Apple's refreshed Human Interface Guidelines. Dated Friends & Fables posts are labelled by year and treated as historical vendor descriptions; no competitor account or campaign was used.
- Product decision: keep the current play board scene-led and the player in control of story pace with Act, Ask, and Pass time. Defer pace settings, broad maps, and dashboard growth until matched QA tasks show a concrete need; prioritize route/presence continuity and bounded old-commitment recall.
- **Evidence boundary:** this is desk research and product triage, not a hands-on competitor study or claim of comparative quality. Sources are linked in `docs/PRODUCT_BENCHMARK.md`.

## 2026-10-02 — Recall indirect “what remains to do?” questions

- A French later-session question, “Qu’est-ce qu’il nous reste à faire ?”, selected an older resolved Lyra commitment as well as the relevant active obligation because no bounded remaining-work cue classified the query.
- Added a paired English, Spanish, and French cue (remaining/left + do, queda + hacer, reste + faire). Requiring both parts keeps “What wine remains?” from retrieving unrelated active commitments. Active typed commitments remain bounded by the existing per-visibility detail cap.
- A production `Play.submit_turn` fake-provider regression verifies source-event provenance for the relevant active commitment and metadata-only treatment for the resolved commitment and ordinary fact decoys across all three languages. A context compiler regression verifies the paired cue and its single-word decoys.
- **Checks:** `play_test.exs` and `context_budget_test.exs` passed (**116 tests, 0 failures**); warnings-as-errors test compilation, format check, and `git diff --check` passed. Tests used isolated `storyteller_test` fixtures and fake providers; no development campaign, Vineyard data, OAuth, or live model request was used.

## 2026-10-02 — Keep slow GM streams attached to the saved turn

- The shared HTTP boundary's 20-second receive timeout also applied to the Responses SSE stream. Separately, each resolving turn's fixed 120-second lease expired even when the provider was still sending output, allowing a reconnect to start another attempt while the original response remained active.
- GM response reads now allow up to 90 seconds between chunks; OAuth and model-catalog requests keep their shorter default. Stream activity refreshes the in-flight attempt lease at most every 30 seconds, and the database update is fenced by turn ID and attempt number. A healthy long response therefore remains attached to its saved turn; an idle stream still times out and follows the existing same-turn recovery path.
- Added adapter coverage for the dedicated stream timeout and activity callback, a play-boundary check that renews an expired fake stream lease, and a reconnect journey that keeps the submitted action visible without starting another provider attempt. Superseded attempts are fenced: a captured old callback cannot renew the newer lease, and either its late success or failure leaves the newer resolving turn and empty timeline untouched.
- **Checks:** focused WSL adapter, play-domain, and LiveView regressions passed (**179 tests, 0 failures**); the full isolated suite passed (**416 tests, 0 failures**). Warnings-as-errors compilation, formatting, Gettext freshness, and `git diff --check` passed. The test runtime was capped at four schedulers to keep its PostgreSQL pool within local connection limits. All inference uses fake providers and isolated `storyteller_test`; no live model, OAuth, or persistent campaign data was used.

## 2026-10-02 — Recall active next steps across sessions

- Later-session prompts such as “What should we do next?” did not reliably retrieve an older active agreement unless the prompt reused the commitment’s original subject words; shared topic words could also expand ordinary facts.
- Added bounded English, Spanish, and French next-step cues that retrieve active typed commitments. Same-topic facts, unrelated facts, and resolved commitments stay compact.
- A production `Play.submit_turn` fake-provider regression verifies all three languages, source-event provenance, decoy omission, the continuity omission marker, and the existing 24,000-byte conservative input bound.
- **Checks:** focused regression passed; `play_test.exs` passed (**94 tests, 0 failures**); `context_budget_test.exs` passed (**19 tests, 0 failures**); the full WSL suite passed (**413 tests, 0 failures**). Formatter check, warnings-as-errors compilation, Gettext freshness, and `git diff --check` passed. Tests used fake providers and isolated `storyteller_test` fixtures; no campaign data, live model request, or OAuth flow was used.

## 2026-10-02 — Recall cross-session work plans

- A player could ask “What was our plan again?” in a later session and lose the agreed action when the question and commitment shared no subject words.
- Added reviewed English, Spanish, and French plan/intention cues that retrieve active typed commitments. Retrieval stays bounded to the latest eight detailed entries per visibility; completed commitments and ordinary facts that merely mention a plan remain compact metadata.
- Added compiler-level coverage for localized paraphrases and decoys, plus a production `Play.submit_turn` fake-provider regression that saves a plan, starts a later session, asks the English plan question, and verifies the commitment detail and source-event provenance arrive while same-topic and unrelated facts stay compact. The request's estimated serialized-byte size remains under Storyteller's configured 24,000-byte preflight bound.
- Documented a dedicated `MIX_TEST_PARTITION=qa` database for persistent browser QA so it cannot contaminate the default ExUnit database.
- **Checks:** focused GM context and Play suites passed (**112 tests, 0 failures**); the full WSL suite passed (**412 tests, 0 failures**). `MIX_ENV=test mix compile --warnings-as-errors`, `mix format --check-formatted`, Gettext extraction freshness, and `git diff --check` passed. Tests used `storyteller_test` and fake providers; no live model request, OAuth, development campaign, or Vineyard campaign was used.

## 2026-10-02 — Verify voice-note persistence in a real browser

- After a report that voice and mannerism edits were not persisting, repeated the edit-save-reload flow in a real browser against the fictional Quiet Observatory QA campaign (campaign 50262) in the isolated `storyteller_test` database. The test server used a fail-closed fake provider; no GM inference was requested.
- Saved Keeper Elin's mannerism, reloaded the editor, then saved her accent on a later visit and reloaded again. Both exact values remained in their fields, and a direct read of the QA test database confirmed both persisted.
- This did not reproduce a persistence defect in the current code. Existing LiveView coverage also exercises multi-character partial updates, clearing a mannerism, save errors, editor remounts, and delivery into later GM context. The player's exact sequence/running app instance remains the unresolved difference; saved guidance affects future GM requests and does not rewrite earlier story messages.
- Rechecked with both accent and mannerism changed in the real LiveView form on a separate server using `storyteller_testqa`: the success status appeared, both exact values were still in the editor after a page reload, and a direct QA database read matched. The new report still does not reproduce on this source revision; the difference appears tied to the running app/session or the exact interaction sequence.
- **Checks:** real-browser save/reload verified for separate mannerism and accent edits; the isolated full WSL suite on the same source revision passed (**410 tests, 0 failures**). No development database, campaign 1, Vineyard campaign, live model, or OAuth was accessed.

## 2026-10-02 — Reject clear narration-only NPC teleportation

- The continuity audit found that canonical presence checks covered public dialogue and activities, but missed narration that said an off-scene character was physically acting at the player's current location. Added a proposal-validation check before the turn transaction commits.
- The regression builds a fictional Finca/Bodega route with Lyra at the Finca and the player at the Bodega. English, Spanish, and French narration that puts Lyra at the Bodega doorway is rejected without adding a story event or changing canon; an ordinary recollection of Lyra's advice is accepted.
- A unique distinctive token from a multiword public GM character name also catches familiar shorthand. A shared token such as “Lyra” becomes ambiguous when another public GM character shares it, and generic role/title words such as “keeper” alone do not identify a character; precise full-name claims still validate.
- This check is deliberately lexical: it combines a character name, a current-scene/location cue, and a present-action cue while allowing sentences that name another public place. It reduces a tested class of hallucinations, but does not understand prose generally and can miss paraphrases or flag ambiguous sentences. Broader language understanding remains open.
- **Checks:** focused fake-provider regression passed (1 selected, 0 failures); the full isolated WSL suite passed (**410 tests, 0 failures**). Formatting, `MIX_ENV=test mix compile --warnings-as-errors`, Gettext extraction freshness, and `git diff --check` passed. Test fixtures use isolated `storyteller_test`; no campaign data, development database, live model, OAuth flow, or Vineyard campaign was used.

## 2026-10-02 — Put canon corrections beside public values

- The audited correction form was hidden below the play board, so correcting an item or resource required opening the panel, choosing its type, finding the target, and re-entering the current value.
- Added a restrained **Correct** link beside each public inventory item and tracked resource. It opens the correction panel with the matching target selected and its current quantity or value prefilled; the player can then enter a reason and make the existing auditable correction. GM-private items receive no public link, and corrections remain unavailable while a turn is unresolved.
- If another session changes tracked state before a correction is submitted, the board and revision now refresh while the player's draft remains open for review and retry.
- The LiveView regressions now enter through the contextual links, verify target selection and prefilled values, and complete both an inventory detail edit and a resource correction without adding story events.
- **Checks:** focused `SessionLiveTest` passed (**63 tests, 0 failures**) and localized LiveView tests passed (**11 tests, 0 failures**); the full WSL suite passed (**409 tests, 0 failures**). `MIX_ENV=test mix compile --warnings-as-errors`, formatting, Gettext extraction freshness, and `git diff --check` passed. All play data used isolated `storyteller_test` fixtures and a fake provider.

## 2026-10-02 — Validate OAuth codes before persisting registration

- A loopback callback with valid state and an issued client ID could omit its authorization code yet persist that unverified ID. A later sign-in would reuse it, potentially preventing first-time registration from recovering.
- The callback now rejects missing, empty, or whitespace-only codes before persisting the ID. Persistence still happens before token exchange, so an issued ID remains reusable when exchange fails transiently.
- Added a fake-OIDC regression that retries after each incomplete callback and verifies registration still uses the dynamic client and its first-registration hint.
- **Checks:** focused WSL OAuth suite passed (**20 tests, 0 failures**); the full isolated suite passed (**408 tests, 0 failures**). `mix format --check-formatted`, `MIX_ENV=test mix compile --warnings-as-errors`, and `git diff --check` passed. Tests used fake OIDC responses and no live OAuth consent, token exchange, or inference.

## 2026-10-02 — Recall known details when travel and looking happen together

- Observation recall used only the scene the player occupied before the turn, so an explicit “go to the Bodega and look around” action could reach the destination while the GM prompt omitted older facts established there.
- Added a bounded arrival anchor for an Act action only when it names a public destination, a public direct route connects it to the current public place, and an explicit travel cue appears before the destination. Ask GM questions and speculative phrasing without that affirmative cue stay at the current vantage; private destinations/routes and other connected places are excluded.
- A production `Play.submit_turn` regression reproduces the old omission, verifies the destination fact is retrieved after 50 unrelated events, rejects a same-wording Copper Archive decoy, and checks canonical arrival and the 40-minute route floor. The same behavior is covered with Spanish and French travel/look phrasing. Requests remain under the configured serialized-byte bound.
- **Checks:** focused English/Spanish/French production-boundary cases passed (**2 selected, 0 failures**); full WSL suite passed (**407 tests, 0 failures**), including Play and context-budget coverage; formatter check, warnings-as-errors compilation, and `git diff --check` passed. Tests use fictional fixtures, `storyteller_test`, and fake providers; no live campaign, model request, OAuth, or Vineyard data was used.

## 2026-10-02 — Clarify character voice setup and edit-save feedback

- Replaced the generic character voice length-limit helper in campaign setup, existing-character edit cards, and the add-character card with a concise example of audible cues: measured pauses, short phrases, and careful word choice. The helper says these profiles guide GM delivery and discourages phonetic spelling and stereotyped accents; live character counts still communicate the limits.
- Updated Spanish and French copy. When a campaign field error rejects the atomic save, the edit page now shows an explicit save-failed alert and keeps the voice draft visible so the player can correct the form without losing their notes or mistaking it for a successful save.
- Added rendered coverage for setup/edit guidance and translations, rejected-save feedback, retained drafts, and persistence of all five fields through reload into later GM context.
- **Checks:** authoring and locale LiveViews **30 tests, 0 failures**; full WSL suite **405 tests, 0 failures**; warnings-as-errors compile, formatter, Gettext freshness, and `git diff --check` passed. All test data was created in isolated `storyteller_test`; no development campaign data or live provider request was accessed.

## 2026-10-02 — Recall natural French future-meeting questions

- Added the French present-plural forms “rencontrent” and “retrouvent” to the bounded meeting concept. A later-session question such as “Où se retrouvent-ils demain ?” can now retrieve a typed public meeting commitment without restating names or location.
- Extended both compiler-level and production-boundary fake-provider regressions across English, Spanish, and French. Same-topic ordinary appointment facts stay compact, unrelated commitments are excluded, and the 24,000-byte conservative preflight bound remains enforced.
- **Checks:** focused context-budget and play suites passed (107 tests, 0 failures); the full WSL `MIX_ENV=test mix test --max-cases 1` suite passed (403 tests, 0 failures); formatter check and warnings-as-errors compilation passed.

## 2026-10-02 — Add a GM character from campaign edit

- The campaign editor has a collapsed add-character panel for an owner to enter a required name, optional player-visible facts, GM-only notes, and the five per-character voice-guidance fields. A selector offers only existing public canonical places; blank remains unplaced. Speaker IDs are generated on the server and made unique against the campaign roster.
- Character creation joins the existing atomic authoring-correction transaction. New notes or voice guidance set the correction's private flag and keep it out of public correction history; public projections omit those fields. Invalid place IDs and over-limit voice guidance preserve the draft and commit no campaign or character changes. Creation is blocked during an unresolved turn so an older GM response cannot treat a new character as present.
- Adding a character does not create a story event or change the elapsed world clock. The acceptance criteria now cover public-place selection, unknown presence, audit privacy, rollback, localized editor labels, and delivery of a saved voice profile to a fake-provider GM request.
- **Checks:** `CampaignAuthoringLiveTest` and `LocaleLiveTest` passed (**28 tests, 0 failures**); the full isolated WSL test suite passed (**403 tests, 0 failures**). Gettext extraction freshness, formatting, warnings-as-errors compilation, and `git diff --check` passed. Tests use `MIX_ENV=test`, `storyteller_test`, and a fake provider. No dev/live database, port 4000, real model request, OAuth, or Vineyard campaign/data was used.

## 2026-10-02 — Prove the player-clicked D20 in a new campaign

- Added a fictional wizard-to-play journey through the GM-led opening and a player action that requests a Balance check at Hard difficulty, target 14. The submitted action stays visible while the initial GM response waits and while the after-roll response is resolving.
- The D20 source is untouched before the player clicks. That click records the fake result once, passes it into the after-roll request, and completes the turn with one player-action event, one roll request, one player-roll event, and the two GM narration beats.
- **Checks:** focused journey passed (**1 selected, 0 failures**); all CampaignLive tests passed (**21 tests, 0 failures**); changed test file format check and `git diff --check` passed. WSL `MIX_ENV=test` uses `storyteller_test` and a deterministic fake provider/roll source; no dev database, port 4000, live model, OAuth, or Vineyard data was used.

## 2026-10-02 — Show campaign edit outcomes beside Save

- Campaign edits now show a clear success status or blocking save error beside the form actions, where the player is already looking after saving. This replaces relying on a page-level flash at the top of the long editor; validation errors keep the draft visible and do not partially save voice notes.
- Behavioral coverage asserts an edited character's notes are saved and reopened with an inline success status, while an over-limit save shows the inline alert and leaves stored notes unchanged. Existing coverage verifies the saved voice guidance is delivered to future GM context.
- **Checks:** focused `CampaignAuthoringLiveTest` passed (12 tests, 0 failures); full WSL suite passed (395 tests, 0 failures); format, gettext extraction freshness, test-environment warnings-as-errors compilation, and `git diff --check` passed. Tests used fictional records, isolated `storyteller_test`, and fake providers only.

## 2026-10-02 — Keep plan-pause resume separate from retry

- Strengthened the opening-scene pause regression with a fake-provider call sentinel. Clearing the account pause does not call the GM; the saved opening remains failed and retryable, and the explicit Retry click is the action that calls the fake provider.
- Source inspection found no production defect: resume reconciles outstanding pending turns into saved failed turns before clearing the pause. No turn-resolution or request behavior changed. The existing acceptance criteria already require resume itself to make no provider call.
- **Checks:** SessionLive passed (**62 tests, 0 failures**); WSL formatter check and `git diff --check` passed. Tests use the isolated `storyteller_test` database and fake provider only; no dev database, port 4000, live account, model request, or Vineyard campaign was used.

## 2026-10-02 — Carry a multi-day passage into the next session

- Extended the fictional setup-to-session LiveView journey: after the GM-led opening and a player action, the player chooses **Pass a few days**. The fake GM advances the canonical date/time and exact clock by three days, while the player character stays in place and does not speak, act, or roll.
- The new session board retains the accepted date/time and passage story. Its next fake-GM request receives the updated canonical world, elapsed clock and anchor, plus the originating time-passage event and narration from the previous session. The test also asserts one passage turn with no duplicate, player-action, or roll event.
- **Checks:** the integrated setup journey passed; all CampaignLive tests passed (**20 tests, 0 failures**); the campaign LiveView test file is formatted; test-environment warnings-as-errors compilation and `git diff --check` passed. Elixir checks use WSL and isolated `storyteller_test` fixtures with a fake provider; no dev database, port 4000, live model, OAuth, or Vineyard data was used.

## 2026-10-02 — Keep known scene cues when one condition is unspecified

- Scene artwork now composes time and weather independently. A known midnight still shows a moon when weather is unrecognized, and known mist or rain remains visible when the time of day is unclear; only a scene with neither dimension recognized receives the fully neutral cue.
- Added rendered LiveView coverage for both partial-cue cases and the fully unknown fallback. The adjacent written game-time and weather remain authoritative.
- **Checks:** Full `SessionLiveTest` suite passed (62 tests, 0 failures), and the full WSL suite passed (395 tests, 0 failures); format check, `MIX_ENV=test mix compile --warnings-as-errors`, and `git diff --check` passed. Tests used isolated `storyteller_test` fixtures only; no dev database, live model, or OAuth was used.

## 2026-10-02 — Clarify the GM model's reasoning setting

- The account settings already showed the preferred or automatically selected GM model, but did not explain its reasoning effort. Added a localized note stating that Storyteller sends no explicit effort override and the selected model's default applies. This is kept in account/model settings and does not change latency or quality behavior.
- Added English, Spanish, and French page assertions using the fake account model catalog. The clarification adds no inference call and does not alter the model request.
- **Checks:** `AuthControllerTest` passed (7 tests, 0 failures), including the account model summary and the new note in all three interface locales. The full isolated suite passed (394 tests, 0 failures). `mix gettext.extract --check-up-to-date`, `mix format --check-formatted`, `MIX_ENV=test mix compile --warnings-as-errors`, and `git diff --check` passed. Tests used the fake model catalog and isolated auth-test credentials; no live model or OAuth call was made.

## 2026-10-02 — Recall agreement nouns across supported languages

- Extended the production-boundary long-campaign commitment regression with “¿Cuál fue nuestro acuerdo?” and “Quel était notre accord ?”. Before adding aliases, the English, Spanish, and French decision forms passed, then the Spanish noun form reproduced an omission of the saved commitment detail; the French noun form is now covered by the same regression.
- Added only the reviewed lexical forms `acuerdo(s)` and `accord(s)` to the existing typed-commitment concept. The same-topic decision fact and unrelated fact remain compact; the matching commitment retains its source sequence. This remains bounded cue matching, not semantic search.
- **Checks:** before the aliases, the extended production-boundary regression reproduced the recall miss (1 selected test failed as expected). Afterward, the focused case passed; Play and ContextBudget modules passed (107 tests, 0 failures); the full suite passed (394 tests, 0 failures). Formatting, test-environment warnings-as-errors compilation, and `git diff --check` passed. Tests used WSL `MIX_ENV=test` with the isolated `storyteller_test` database and injected fake providers; no dev database, port 4000, Vineyard campaign, live model, or OAuth was used.

## 2026-10-02 — Exercise voice edits across multiple character cards

- Hardened the campaign-editor regression for the reported voice/mannerism persistence issue. The native rendered form now exercises edits to all five guidance fields on one character and edits plus a cleared mannerism on another, followed by a partial validation and a save without replaying the full form values.
- The test verifies both saved database maps and all remaining values after mounting a fresh edit page. It uses fictional fixture characters and the isolated test database; no application code or campaign data changed in this slice. The current edit handler already strips Phoenix `_unused_*` markers and merges drafts before validation/persistence.
- **Checks:** focused `CampaignAuthoringLiveTest` passed (12 tests, 0 failures, 11 excluded); full WSL `MIX_ENV=test mix test --max-cases 1` passed (393 tests, 0 failures); formatter check, warnings-as-errors compilation, and `git diff --check` passed. Tests use the isolated `storyteller_test` database and fictional fixtures only.

## 2026-10-02 — Carry vineyard resources into the next session

- Added a player-facing regression for the resource campaign contract: selling reserve wine applies a money increase to the Finca cash panel and a stock decrease to the Bodega cellar panel. Change receipts stay beside their values, not in the story timeline.
- The later session shows both updated balances, and its next fake-provider request receives those canonical values. This covers the vineyard/resource genre through the LiveView and production turn boundary; it uses a fictional QA fixture rather than the owner's Vineyard campaign.
- **Checks:** focused WSL LiveView regression passed (1 selected, 60 excluded); full `SessionLiveTest` passed (61 tests, 0 failures); full WSL `MIX_ENV=test mix test --max-cases 1` passed (394 tests, 0 failures); formatter check, warnings-as-errors compilation, and `git diff --check` passed. Tests use the isolated `storyteller_test` database and injected fake providers only.

## 2026-10-02 — Bring the player character onto the play board

- The play page showed “Playing as [name]” in its header, while the description and personal facts were buried in the generic, collapsed Characters list. Added a compact “Your character” card beside the scene and inventory with the player's name and public description, three stable public facts, and a disclosure for additional details; the mobile section bar links directly to it.
- The card uses the existing in-place panel cue for changed character details. Its regression verifies name, description, a tracked Health value, overflow disclosure, and exclusion of a GM-private motive.
- **Checks:** focused LiveView regression passed (1 selected, 59 excluded); full SessionLive suite passed (60 tests, 0 failures); full WSL `MIX_ENV=test mix test --max-cases 1` suite passed (392 tests, 0 failures). WSL formatting, warnings-as-errors compilation, and `git diff --check` passed for the combined iteration.

## 2026-10-02 — Recall a French star-chart fact from English, Spanish, or French

- A production-boundary fake-provider test found that a French public continuity note about “la carte des étoiles” was omitted when later asked in English, “Where did we hide the star chart?” The detail selector compared individual lexical tokens and had no reviewed cross-language phrase for the paired idea.
- Added one bounded `star chart` concept requiring both a celestial term and a chart/map term on the query and note. English, Spanish, and French asks now retrieve the French-authored fact and its source sequence. A follow-up paraphrase check found that `constellation map`, `mapa de constelaciones`, and `carte des constellations` still missed; added those reviewed aliases, including accented and unaccented Spanish forms. Same-locale chart-only and star-only decoys retain only identity/status metadata. A similarly worded GM-private note remains in the private prompt section and is absent from the public continuity list.
- The regression stores the note through a real accepted turn, then exercises later production `Play.submit_turn` requests after 100 synthetic sessions and 2,400 unrelated persisted events. It checks all 12 newest events on the first recall, source provenance, and the configured 24,000-byte conservative input bound for each locale. This adds a reviewed compound lexical cue, not general translation, paraphrase understanding, or semantic search.
- **Checks:** before the base fix, the focused regression reproduced omission of the French detail (1 selected test failed as expected). The follow-up regression reproduced the constellation paraphrase miss before the alias change; afterward all six English, Spanish, and French questions passed (1 selected test, 0 failures; 88 excluded). The full Play and ContextBudget modules passed (107 tests, 0 failures). Formatter check, test-environment warnings-as-errors compilation, and `git diff --check` passed. Tests use `MIX_ENV=test`, isolated `storyteller_test`, and an injected fake provider; no development DB, port 4000, campaign/Vineyard data, live model, or OAuth was used.

## 2026-10-02 — Keep observation recall within the current scene

- Added a bounded observation-question cue list for common English, Spanish, and French forms of see/look/notice/inspect/hear/smell/feel. Older history for those questions is retrieved through the current place and co-present character anchors; connected-place names and isolated wording matches cannot make a remote detail appear visible. Other turn retrieval keeps its existing connected-place and action-term anchors.
- Added a production `Play.submit_turn` fake-provider regression with 2,400 saved events. Direct and indirect English questions plus “¿Qué puedo ver aquí?” and “Qu’est-ce que je peux voir ici ?” retain an older current-place chart detail while omitting 50 same-wording events and a trapdoor at the connected Copper Archive. A question with no current-scene evidence receives an uncertainty answer. The scenarios preserve canonical place, character, world, and clock data and stay within the 24,000-byte serialized-input bound.
- **Checks:** the focused observation case passed (1 selected, 0 failures); Play, ContextBudget, and long-campaign continuity suites passed (107 tests, 0 failures). The full WSL `MIX_ENV=test mix test --max-cases 1` suite passed (390 tests, 0 failures) against the isolated `storyteller_test` database. Formatting, warnings-as-errors compilation, and `git diff --check` also passed.

## 2026-10-02 — Keep the development signing key out of source control

- Removed the fixed development cookie-signing key from tracked config. Development now creates or reuses a persistent per-installation key in the user's local config directory, with owner-only file and directory permissions; an explicit `SECRET_KEY_BASE` override remains available. Invalid existing key files are rejected rather than silently rotated, avoiding unexpected session invalidation.
- Added ignore rules for local ChatGPT credential and development-key files, and documented the external key path and override. Production continues to require its environment-provided signing key.
- **Checks:** local-secret tests passed (3 tests) for creation, persistence, restrictive permissions, permission repair without rotation, and malformed-key rejection. A dev-config smoke check verified isolated key creation and environment override without starting the app or database. The full WSL `MIX_ENV=test mix test --max-cases 1` suite passed (390 tests, 0 failures); formatting, warnings-as-errors compilation, and `git diff --check` passed. No OAuth credentials, live provider call, or campaign data were used.

## 2026-10-02 — Recall canon from natural questions about absent characters

- Strengthened the production-boundary `Play.submit_turn` regression across 100 sessions and 2,400 saved events. The player asks “Could Marisol join us here for the pressing?” without restating her location, the route, travel time, or duty.
- When an action explicitly names a GM character at a different canonical place, older-event retrieval now requires the event to refer to that character. This keeps same-place pressing decoys from displacing the relevant Finca/Bodega history; requests without a named away character retain the existing bounded scene-anchor scoring.
- The regression verifies the older location/duty evidence, all 12 newest story events, canonical Marisol location/duty and route, exclusion of eight same-place/topic decoys, and the configured 24,000-byte preflight bound. Added the matching UX acceptance criterion. This is a narrow entity-focused cue, not general semantic search.
- **Checks:** production-boundary regression passed (1 selected, 0 failures); ContextBudget and long-campaign continuity suites passed (**19 tests, 0 failures**); full `PlayTest` suite passed (**87 tests, 0 failures**); `mix compile --warnings-as-errors`, `mix format --check-formatted`, and `git diff --check` passed. Elixir commands used WSL with `MIX_ENV=test` and the isolated `storyteller_test` database; no dev database, port 4000, live campaign, model request, OAuth, or Vineyard campaign was used. The full repository suite was not run for this slice.

## 2026-10-02 — Follow a new campaign into its next session

- Added one integrated fake-provider LiveView journey that creates a fictional campaign through the actual setup wizard, accepts the GM-led opening at the configured public location, and carries a starting owned item into play.
- A player action consumes one item through the validated inventory path. The play board shows the remaining quantity; after starting a later session, the earlier action and GM narration, current place, and remaining item remain visible. A subsequent player move confirms the later GM request receives the current inventory quantity.
- This test covers user flow and canonical continuity, not live-model writing quality, latency, OAuth, or account eligibility. It uses no persistent campaign data.
- **Checks:** focused journey passed (1 selected, 0 failures); the full isolated WSL suite passed (386 tests, 0 failures), including CampaignLive (20), SessionLive (59), and CampaignAuthoringLive (11); formatting, Gettext freshness, test-environment warnings-as-errors compilation, and `git diff --check` passed. Elixir commands used the isolated `storyteller_test` database and fake provider; no dev database, port 4000, live model, OAuth flow, or Vineyard campaign was used.

## 2026-10-02 — Keep current companions in view on the scene board

- The scene card previously hid present characters and their activity under place lore, and the separate character list was also collapsed. The board now shows up to three canonically co-present public companions with their current visible activity; any larger cast stays behind a collapsed “See more” disclosure. Place description and facts remain in the separate collapsed Place details section, and the duplicate people list was removed.
- Added behavioral LiveView coverage for initial co-presence versus an off-scene character, GM-private fact exclusion, large-cast overflow, and a fake-provider activity update appearing in the at-a-glance strip after a turn. Spanish and French locale assertions cover the translated labels; locale session tests now finish their fake opening turn before sandbox teardown.
- **Checks:** new companion-strip scenarios (**2 tests, 0 failures**); SessionLive suite (**59 tests, 0 failures**); LocaleLive suite (**9 tests, 0 failures**); full isolated WSL suite (**385 tests, 0 failures**); formatter, Gettext freshness, warnings-as-errors compilation, and `git diff --check` passed. All Elixir checks used `MIX_ENV=test` and isolated `storyteller_test`; no dev database, port 4000, live provider, OAuth flow, or Vineyard campaign was used.

## 2026-10-02 — Keep character voices distinct and route setup errors to their step

- The GM policy now directs the model to keep each speaker's own accent/dialect, vocabulary, cadence, quirks, and mannerisms recognizable without blending profiles, flattening the cast into one voice, or using phonetic caricature. The policy addition is concise because it is repeated in each GM request.
- Character voice profiles remain attached to their own present character through the production context builder and context compaction. A regression checks the actual request instructions and distinct voice guidance for two contrasting NPCs. Live model output was not requested, so audible/visible voice distinctness remains a human play-review item.
- Campaign setup now routes changeset errors for starting location, date, time, and weather back to the Opening scene step, rather than the final People and details step. A rendered-form regression enters overlong weather, verifies the correction step and field error, and confirms no campaign is created.
- **Checks:** full isolated WSL suite passed (**383 tests, 0 failures**); focused Play and campaign-authoring suites passed (**98 tests, 0 failures**); GM context-budget suite passed (**18 tests, 0 failures**); formatter, Gettext extraction freshness, warnings-as-errors compilation, and `git diff --check` passed. Tests used `storyteller_test` and fake providers; no live model request, OAuth consent, or Vineyard campaign was used.

## 2026-10-02 — Keep the play board anchored while history scrolls

- On roomy desktop viewports, the central play column could scroll far enough to move the composer away from the world and campaign panels. Keep the main column anchored and make the story timeline the history scroll surface; retain normal page scrolling on narrow or short viewports.
- Added a layout regression for the desktop breakpoint and scroll ownership. Existing panel-pulse coverage now also catches objective status-only changes, and the related LiveView regression keeps objective audit details out of story chat.
- **Checks:** full isolated WSL suite passed (**382 tests, 0 failures**); objective status LiveView regression (**1 selected, 0 failures**) and layout regression (**1 test, 0 failures**) passed; panel hook unit tests passed (**3 tests, 0 failures**) in Windows Node. Formatter check, warnings-as-errors test compilation, and `git diff --check` passed. No live campaign, provider request, or OAuth flow was used.

## 2026-10-02 — Cue objective status changes in the campaign panel

- Objective rows kept the same watched text when their status changed, even though they moved between Open, Completed, and Abandoned groups. The panel hook therefore skipped its change pulse and live announcement when only status changed.
- Objective panel watches now include status alongside displayed text. Status transitions pulse and announce in the Objectives panel; the state audit remains outside the story timeline.
- Added a fake-provider LiveView regression for an open objective becoming completed, plus a panel-hook unit test that verifies a status-only change triggers the pulse.
- **Checks:** the focused fake-provider objective-status LiveView regression passed (**1 selected, 0 failures; 56 excluded**), and the panel hook unit suite passed (**3 tests, 0 failures**). Test-environment warnings-as-errors compilation, formatter check, and `git diff --check` passed. LiveView behavior uses the isolated `storyteller_test` database; no live provider, campaign, or OAuth flow was used.

## 2026-10-02 — Require a known player scene for NPC dialogue

- A missing canonical player place was being treated as if every NPC were present. A fake-provider behavior regression reproduced a completed turn with public dialogue and activity from an NPC whose canonical place was Finca while the player had no known place.
- Public NPC speech and activity now require a known player scene and a matching final canonical location. An unresolved place is not evidence of co-presence; the player's own line and separately validated remote-message events keep their existing behavior.
- The regression asserts that the turn fails safely, preserves the submitted action for recovery, leaves the NPC's location and world clock unchanged, and adds no NPC dialogue or activity. The existing LiveView retry-card regression also passed.
- **Checks:** 4 focused continuity/recovery tests passed (143 tests discovered, 0 failures, 139 excluded); formatter, warnings-as-errors compilation, and `git diff --check` passed. All tests use `MIX_ENV=test`, the isolated `storyteller_test` database, and fake providers; no live model call or OAuth flow was used.

## 2026-10-02 — Recall campaign decisions in English, Spanish, and French

- Added a small reviewed vocabulary for common decision wording, including “What did we decide?”, “¿Qué decidimos?”, and “Qu’avons-nous décidé ?”. These cues retrieve typed campaign commitments without broadening ordinary facts that merely mention a decision.
- Extended the production `Play.submit_turn` regression across later sessions in all three locales. The earlier agreement and provenance reach each fake-provider request; a same-topic ordinary fact and an unrelated fact keep identity/status metadata only. Each request remains within the 24,000-byte conservative serialized-byte bound.
- **Limit:** other inflections, indirect phrasings, and general semantic retrieval remain open; these aliases are not a general intent detector.
- **Checks:** focused production-boundary test passed (86 tests, 1 selected, 85 excluded); full WSL suite passed (379 tests, 0 failures); warnings-as-errors compilation, formatter check, and `git diff --check` passed. Tests used only the isolated test database and fake provider; no live model request or OAuth was used.

## 2026-10-02 — Save character voice notes from the campaign editor

- Phoenix LiveView adds `_unused_*` markers for untouched nested form inputs during change events. Those markers were retained in the editor draft and later rejected by strict authoring validation, so real browser saves showed a false voice-limit error and did not persist the notes.
- The editor now strips only those framework markers from authoring drafts and submit data before validation. Other unexpected keys still reach the strict validators and remain rejected.
- Expanded the behavioral regression with realistic unused markers across character facts, active duties, and all voice fields. It proves a later partial submit saves the voice notes to the character and a reopened edit form reads them back. A local browser repro against the isolated `storyteller_test` database also confirmed the failure before the fix and successful save/reload afterward; no live model request was made.
- **Checks:** WSL targeted edit tests (10 passed), full suite (379 tests, 0 failures), warnings-as-errors compilation, formatter check, Gettext extraction/freshness, and `git diff --check`. A real edit/save/reload in the browser was verified against the isolated `storyteller_test` database; synthetic QA rows and the temporary server were removed afterward.

## 2026-10-02 — Recall a prior agreement from “What did we decide?”

- Added bounded English `decide`/`decided` aliases for typed campaign commitments, so a later-session question can retrieve an earlier agreement even when its saved details say “agreed.” The shared typed concept does not expand detail retrieval for an ordinary fact merely because it also says “decided.”
- Added a fake-provider regression through production `Play.submit_turn`: the older agreement and provenance reach GM context, while a same-topic decision stored as an ordinary fact and an unrelated fact retain identity/status only. The request is checked against the 24,000-byte conservative serialized-byte preflight bound.
- **Limit:** this proves the exact question “What did we decide?” and the note-side past tense “decided.” Other English forms, Spanish/French decision wording, other paraphrases, and broad semantic retrieval remain open; no semantic-retrieval claim is made.
- **Checks:** WSL `MIX_ENV=test mix test` (379 tests, 0 failures), warnings-as-errors compilation, formatter check, Gettext freshness check, and `git diff --check`.

## 2026-10-02 — Show nearby places on the scene board

- The scene board now lists public places one canonical route away from the player's current place, with the route's in-world travel time. Longer lists collapse after three destinations to keep the board concise.
- The public projection omits private routes and private destinations. A LiveView regression exercises both privacy cases and verifies Spanish and French labels.
- **Checks:** focused route/privacy/locale LiveView regression passed; full SessionLive suite passed (**56 tests, 0 failures**); test-environment warnings-as-errors compilation, formatter, Gettext freshness, and `git diff --check` passed. All Elixir commands ran in WSL against the isolated `storyteller_test` database; tests used fake providers only.

## 2026-10-02 — Make combined character voice limits visible

- A profile can stay below each field's 280-character HTML limit while exceeding the server's 1,200-character total and being rejected. Campaign setup and campaign edit now share the validator's limits, show the live per-character total, and warn inline when the combined cap is exceeded. The edit error names both limits and retains the rejected draft; the atomic backend validation remains authoritative.
- Added LiveView coverage for both setup and editing. The edit regression checks the over-limit warning, retained 1,250-character draft, precise save error, and absence of partial database writes. This is a demonstrated reject-without-save path, not confirmation that it was the exact cause of the reported runtime symptom.
- **Checks:** 377 tests passed; test-environment compile with warnings as errors, formatter check, translation-catalog check, and `git diff --check` all passed.

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
- For another look-around, this iteration originally asked for at most one supported new detail. That arbitrary cap was removed on 2026-10-08; current behavior is documented above and in `docs/UX_ACCEPTANCE.md`: provide salient, supported evidence without repetition or exhaustive inventory, with no fixed detail-count ceiling. If nothing can be grounded, say so briefly and return choice with a low-pressure invitation to inspect something specific or choose a next move. Do not manufacture actionable facts for color. A direct question still leaves time and canon unchanged.
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
- **Defining product promise:** structured local canon prevents LLM memory drift, while relevance-ranked context keeps each response coherent as campaigns grow. Campaign continuity and graceful handling of the selected model's actual context limit are acceptance checks; request-size and usage readings are diagnostics, never optimization goals. The first compiler and aggregate provider-usage instrumentation are tracked in the 2026-10-01 context-compiler entry above; exact per-section tokenizer counts remain open.
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
