# Inference Cost Investigation

**Date:** 2026-09-30
**Status:** Investigation only. Cost trimming is deferred until the MVP is functional. No optimization is approved or implemented by this note.

## Purpose

Record the current API-equivalent inference estimate for Storyteller, describe the factors that drive it, and preserve post-MVP optimization ideas for later evaluation.

The earlier $4.88/month figure is a modeled variable inference cost for a heavy-use player, not an observed bill. The current Storyteller integration uses the owner's ChatGPT-plan OAuth allowance, so it does not create a separate per-token API invoice while eligible requests remain within that shared plan allowance. See the [implementation plan](../IMPLEMENTATION_PLAN.md#monthly-inference-cost-estimate).

Strictly, inference spend is per-user serving cost or cost of goods sold (COGS). Customer acquisition cost (CAC) is the marketing and sales spend needed to acquire a player. Reducing inference cost improves unit economics, but it is not itself CAC.

## How a game action uses the model

- A normal player action uses one Responses API call. The result contains narration, dialogue, activity, memory updates, and proposed state changes in one JSON object.
- If the GM requests a player D20 roll, the first call asks for the roll. The player clicks the die, which the app resolves locally; a second model call uses the recorded result to finish the turn.
- Proposal validation, persistence, and ordinary D20 generation are local application work. They do not create additional model calls.
- The request contains the fixed GM policy and a JSON context built from campaign setup, canonical public and GM-private state, characters, places, panels, objectives, continuity, memory summaries, the player's action and roll, and up to 40 recent event records. The event limit is not 40 complete turns, and older campaign history is summarized rather than sent as a full transcript.
- Both public and GM-private context are included in the model request. The application validates the response before committing state.

Relevant code: [turn resolution and context construction](../lib/storyteller/play.ex) and [the Responses adapter](../lib/storyteller/gm/open_ai.ex).

The GM policy is 12,157 source characters, approximately 3,000 tokens using a rough four-characters-per-token conversion. That is a planning approximation, not a GPT-6 Luna tokenizer measurement. The request also includes up to 40 event records, two maintained summaries of up to 6,000 characters each, campaign records, and up to 100 total continuity entries. Actual input size can vary considerably with a campaign's population and history.

## API-equivalent cost assumptions

The current standard GPT-6 Luna API rates are $0.10 per million uncached input tokens and $0.50 per million output tokens. Cached input is $0.01 per million tokens. GPT-6 Luna is a low-cost API comparison example, not a claim that its play quality matches GPT-6 Sol or the ChatGPT-plan route. The estimates below assume 30 play days per month, standard processing, no cache savings, and one call per player action unless the roll-follow-up column is used. They are estimates, not provider usage measurements. See [GPT-6 Luna pricing](https://developers.openai.com/api/docs/models/gpt-6-luna).

Formula:

```text
monthly API cost = 30 × daily actions ×
  (input tokens × $0.10 + output tokens × $0.50) / 1,000,000 ×
  (1 + roll follow-up rate)
```

| Player actions/day | Assumed input/output per call | One call per action | With 15% roll follow-up calls |
| ---: | ---: | ---: | ---: |
| 5 | 12,000 / 1,500 | $0.29/month | $0.34/month |
| 20 | 25,000 / 2,000 | $2.10/month | $2.42/month |
| 25 | 25,000 / 2,000 | $2.63/month | $3.02/month |
| 25, dense context | 50,000 / 3,000 | $4.88/month | $5.61/month |

The $4.88 estimate assumes 25 actions every day, a 50k-input/3k-output request, and no roll follow-ups. If 15% of actions need the second roll-resolution call, the same scenario is about $5.61/month. Conversely, at 5 actions/day with the same dense per-call size, it is about $0.98/month before roll follow-ups ($1.12 at 15%). Actual average player activity is unknown.

## Potential savings to evaluate after the MVP

Savings below use the dense 25-actions/day scenario as a reference. They are approximate and do not establish a target until real usage and game quality are measured.

| Candidate | Approximate effect at 25 actions/day | Tradeoff or uncertainty |
| --- | ---: | --- |
| Reduce input from 50k to 20k tokens/call | Saves $2.25/month without extra roll calls; $2.59 with 15% roll follow-ups | Requires checking that shorter context still preserves scene continuity and private facts. |
| Reduce output from 3k to 1.5k tokens/call | Saves $0.56/month without extra roll calls; $0.65 with 15% roll follow-ups | Could make narration, dialogue, or structured changes too terse. |
| Reuse the repeated 3k-token GM-policy prefix through prompt caching | Saves about $0.20–$0.24/month if every request reuses the cache | Cache hits are not guaranteed. This is a small saving by itself. |
| Request low reasoning effort for supported models | Unknown until usage is measured | Lower effort favors speed and fewer reasoning tokens, but may reduce judgment quality on complex turns. |
| Reduce average free-player activity | Cost scales approximately linearly with calls | A product limit is a pricing/product choice and may reduce engagement. |

One candidate benchmark is 18k input and 1.2k billable output tokens per call. At 25 actions/day with 15% roll follow-ups, that is about $2.07/month without cache hits, or about $1.84 if the repeated 3k-token policy prefix is cached on every call. This is an investigation target only; it must be checked against actual campaign turns and quality before being adopted.

### Context and cache considerations

The current request includes the changing player action in its JSON context. GPT-6 caching benefits only from an unchanged prefix, so a future investigation could test putting stable instructions and setup first and changing action/roll data last. The resulting prefix and cache reuse have not been measured. A more compact context could also include fewer recent narrative events, omit redundant audit records already represented in canonical state, and retrieve only relevant characters, places, objectives, and continuity entries. Preserve authoritative state and visibility boundaries; do not trade away correctness for token savings.

OpenAI documents automatic prompt caching for GPT-5.6 and later models, with a 1,024-token minimum cacheable prefix, a 30-minute default lifetime, and a 90% lower cached-input rate for GPT-6 Luna. Cache writes cost more than uncached input, so reuse frequency matters. The ChatGPT-plan OAuth preview omits persistent provider conversation state and has request-field limitations; confirm actual cache behavior and usage visibility on that route rather than assuming API-key results transfer unchanged. See [prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching) and [OAuth preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).

### Measurement gap

Successful streaming responses expose aggregate `input_tokens` and `output_tokens`. Storyteller emits these numeric values, along with context-section byte sizes, through local Telemetry; it does not persist them per turn or provide a usage report, so they disappear when the running process stops. The adapter's duration-only time-to-first-text-delta timer starts immediately before dispatching the Responses request and stops on the first non-empty text delta. It runs after OAuth token acquisition, model/catalog resolution, and request-body validation, so it excludes those stages while including request setup, network, and provider wait. The LiveView uses that first delta only to change its waiting status; it withholds streamed JSON until the complete response is validated and committed. This is neither a first-valid-narration nor completion measurement, and no local log reporter records this separate delta metric. The adapter currently does not retain cached-input or reasoning-token details, and no per-action cost, retry rate, or cross-session usage trend can be calculated. The interim 64,000-byte local preflight is an application guard chosen to admit a known 31,825-byte valid synthetic shape; it is not an exact tokenizer count or a verified SIWC route ceiling. A follow-up measurement feature should persist only numeric per-turn usage locally, without prompts, private context, or campaign identifiers, before using real turn totals to calibrate the guard. If the OAuth route does not expose the needed details, label that limitation rather than inferring API-key pricing or assuming cache behavior transfers to OAuth. The adapter behavior is visible in [open_ai.ex](../lib/storyteller/gm/open_ai.ex).

The offline context-budget regression now compares 12-event and 240-event synthetic histories with the same player action, production base GM policy, and configured default 64,000-byte bound. Across the 228 older events, its labels include three relevant Finca/Bodega commitments, seven hard decoys that share a character, place, or task term, and 218 unrelated decoys. It asserts recall of all three relevant events and no false inclusions for this fixture (precision 3/3). For concrete queries, the lexical gate requires either two action-specific matches or one action-specific match plus a current-scene/connected-place anchor. For broad actions, a small curated set of generic conversational/time terms is removed first; when fewer than two action-specific terms remain, retrieval falls back to matching current/connected-place and current-scene character/speaker anchors only. Both paths remain capped at eight older events. The cross-session play regression covers the broad case: the query “I ask what needs doing before we close for the evening” retains the older Bodega narration and Lyra dialogue, omits unrelated inserted history, and stays within the configured 64,000-byte preflight bound.

These are deterministic fixture results, not general retrieval quality: the hard decoys share either an action term or a scene anchor, but do not combine both. A false event containing one task term and one current character/place anchor can still pass the concrete-query gate; anchor-only broad questions can also retrieve unrelated events tied to the same scene. Other wording, languages, and campaign shapes need evaluation, and the curated generic-term list is not semantic intent detection.

The test reads the private `@gm_policy` source literal because the application does not expose a callable instruction builder; action mode currently appends no additional guidance. Its byte estimate is `instruction bytes + encoded context JSON bytes + 512 bytes` for framing. It compares the raw full-history context and compiled context under that same estimate, but does not serialize the complete HTTP body or measure provider tokenization. Consequently, the 5× reduction and short-baseline comparison are request-context byte results, not actual provider input-token savings. Completed-response aggregate usage remains observable only through transient runtime Telemetry unless a numeric-only local usage history is added.

Storyteller now requests `low` reasoning effort for recognized GPT-5, GPT-6, and o-series models; other models retain their defaults. OpenAI's ChatGPT-plan preview requirements do not list `reasoning` among unsupported Responses fields, and the reasoning guide says lower effort favors speed and token use while potentially reducing quality. Compare continuity, player-agency compliance, roll requests, state-change accuracy, private-fact handling, response length, latency, and token usage on representative turns before considering a lower setting. See [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) and [reasoning model guidance](https://developers.openai.com/api/docs/guides/reasoning).

## Deferred investigation sequence

1. Make the MVP functional without cost-driven gameplay changes.
2. Measure representative turn usage, cache-hit rates, retries, and roll follow-ups.
3. Identify the largest input contributors and test a smaller, relevance-based context window against game-quality scenarios.
4. Test stable-prefix caching and lower reasoning effort where supported.
5. Compare output compactness and summary-update frequency; keep the narration quality and continuity acceptable.
6. Review average activity across free players before choosing any free-tier call limit.

No model, prompt, context-window, roll, free-tier, or billing behavior is changed by this document.
