---
name: steelman:pre-mortem
description: Use BEFORE locking in an architectural decision, major migration, hot-path refactor, new dependency adoption, or data-model change — while the choice is still reversible. The skill reframes the question in past tense: «move forward two weeks; the decision shipped; it failed catastrophically — what happened?». That framing unlocks «prospective hindsight» and surfaces about 30% more candid risk than forward-looking «what could go wrong?» analysis. Triggers: «давай так сделаем», «let's go with X», «решено» — right before commitment; before starting a major phase, migration, or dependency upgrade; explicit «pre-mortem», «failure modes», «what could go wrong». NOT after the change has shipped — that's post-mortem territory.
---

# steelman:pre-mortem

> **Mandate:** Move forward in time. The decision shipped. Two weeks later, you wake up to find it failed catastrophically. Tell me — what happened?

Based on Klein's pre-mortem technique (HBR, 2007), now standard practice in operational risk analysis.

## Why this framing

Forward-looking risk analysis ("what could go wrong?") is bound by the optimism the team built up while making the decision. People bring up obstacles they're already prepared to solve. The cluster of failure modes nobody mentioned because nobody anticipated them is invisible.

Klein's pre-mortem reframes the question in past tense — **"two weeks from now, this failed, why?"** — which unlocks "prospective hindsight." Studies show this surfaces ~30% more candid risk than the same group asked forward-looking.

The skill applies the same mechanic to AI-assisted architecture decisions.

## Inputs

```bash
/steelman:pre-mortem "<decision description>"
```

Examples:
- `/steelman:pre-mortem "migrate from SQLite to Postgres for the audit table"`
- `/steelman:pre-mortem "introduce LLM-as-judge into the digest publish path"`
- `/steelman:pre-mortem "drop the staging environment to save infra cost"`

If the user is mid-conversation about a decision and says "pre-mortem this" without a quoted decision, infer the decision from the last 3-5 messages.

## Procedure

### Step 1 — Frame past-tense

Convert the proposed decision to past-tense failure framing. Examples:

| Forward-looking | Past-tense failure framing |
|---|---|
| "We're considering migrating to Postgres" | "It's June 1st. The Postgres migration shipped two weeks ago and failed catastrophically. The bot has been down 36 hours. The operator is furious." |
| "We're adopting LLM-as-judge for publish gate" | "It's June 1st. LLM-as-judge has been in publish for two weeks. We just published a digest with a hallucinated indictment. Press picked it up." |

The framing should be:
- **Specific in date** (concrete future date, not "someday")
- **Visceral in consequence** (named the bad outcome — "down 36 hours", "press picked it up")
- **Tied to the operator's actual production context** (use what you know from CLAUDE.md / `.planning/`)

### Step 2 — Spawn pre-mortem jury (3 reviewers, parallel, MARS pattern)

Each reviewer takes a different stance to expand the failure-mode coverage:

| Reviewer | Engine | Stance | Mandate |
|---|---|---|---|
| **The senior engineer who joined six months ago** | Agent-tool Claude subagent (fresh isolated context, model=opus). Never `claude -p`. | Knows the codebase, hasn't drunk the kool-aid on this decision | "Tell me the technical failure modes — what does this break that the team hasn't thought about?" |
| **The on-call who got paged** | `codex exec` via Bash (see `docs/ENGINES.md` §4b for the invocation recipe) | Was at the wrong end of this failure mode | "Walk me through the page-to-resolution. What was the symptom? What was the root cause? Why did it take so long to figure out?" |
| **The skeptic external advisor** | Agent-tool Claude subagent (fresh isolated context, distinct adversarial framing) | No skin in the game | "Why is this decision wrong? Argue from first principles." |

**Codex absent:** all three are Agent-tool Claude subagents. The three distinct stances already provide the independence that matters — context isolation + adversarial framing. Emit the honest single-provider label from `docs/ENGINES.md` §5. Never spawn more than these 3 stances.

Each reviewer returns a list of failure modes with:
- Trigger condition (what initiated the failure)
- Symptom (what the operator saw first)
- Root cause (the underlying gap in the decision)
- Time-to-detect (how long it took to even notice)
- Reversibility (can we roll back; how painful)

### Step 3 — Aggregate (no debate, MARS meta-pass)

Deduplicate by `(trigger, root_cause)`. Rank by:
1. **Reversibility** descending — irreversible failures first
2. **Probability** descending — likely failures first
3. **Time-to-detect** descending — silent failures first (those bite hardest)

### Step 4 — Output

```markdown
# Pre-mortem: {decision}

## The framing
{past-tense visceral framing}

## Top failure modes (ranked by reversibility × probability × silent-fail)

### M1 — {short title}
**Trigger:** {what initiated}
**Symptom:** {what operator saw}
**Root cause:** {underlying gap}
**Time-to-detect:** {minutes / hours / days / weeks}
**Reversibility:** {easy / hard / impossible}
**Mitigation:** {what could be done BEFORE shipping to prevent this}

### M2 — ...

## Pre-shipping mitigations (recommended)
{ordered list — cheapest, highest-impact first}

## Things that did NOT fail (defended-against scenarios)
{explicit — pre-empts the "we already thought of that" dismissal}

## Decision recommendation
**GO** | **GO with mitigations M1-M3 applied first** | **PAUSE — high irreversible failure-mode density** | **PIVOT — consider alternative {X}**

## Methodology
- Reviewers: {3 stances above}
- Past-tense framing: yes (per Klein HBR 2007)
- Time-box: 10 min per reviewer
- Cross-talk: no (MARS pattern)
```

## Anti-patterns to reject

- ❌ Forward-looking framing ("what could go wrong?") — defeats the purpose
- ❌ Asking the people who PROPOSED the decision to do the pre-mortem (proposer-evaluator bias)
- ❌ Vague failure modes ("performance might be slow") — every claim has a trigger + symptom + root cause
- ❌ Skipping the time-to-detect column — silent-fail mode is the most expensive failure class
- ❌ Calling a forward-looking "risk analysis" a pre-mortem — they are different and not interchangeable

## Known blind spot

A pre-mortem reliably surfaces *architectural and operational* failure modes — the past-tense framing is built to expand exactly that space. It is correspondingly **weak on small implementation-level predicate bugs**: string-equality / whitespace mismatches, off-by-one, regex gaps. The framing pulls attention toward «what decision failed», not «what one line is subtly wrong».

Field case (ugolovkin v2.15, 2026-05-19): a pre-mortem on a hotfix design correctly forced a PIVOT to a safer merge rule — then a whitespace-equality bug in the *implementation* of that rule shipped anyway («ч.4 ст.160» vs «ч. 4 ст. 160» normalised to different strings), and was caught only by a later `steelman:full-codebase` pass.

**Mitigation:** a pre-mortem on the design does not substitute for a pass on the code. Before a release or milestone tag, run both — `pre-mortem` on the design, `steelman:full-codebase` (or `attack-fix` on the diff) on the implementation.

## Auto-trigger conditions

- The user's message contains «pre-mortem» / «premortem» / «failure modes» / «что может сломаться»
- The user says «давай делать X» / «let's go with X» AND no prior pre-mortem was run for X
- A `phase-spec` / `decision-doc` / ADR markdown file is being written or committed AND no companion `pre-mortem.md` exists yet

## Engine routing

**Tier: 3 stances (design, not diff) — no static diff gate.**

This skill reviews an architectural decision, not a code diff. There is no LOC-based pre-gate; the decision to run pre-mortem is already the operator's explicit call.

- **Codex present:** "senior engineer" = Claude Agent-tool subagent; "on-call" = `codex exec`; "skeptic" = Claude Agent-tool subagent. All three run in parallel, isolated (MARS pattern).
- **Codex absent:** all three are Agent-tool Claude subagents. The three distinct stances provide context isolation and adversarial framing — the two interventions that cut sycophantic review. Emit the honest single-provider label from `docs/ENGINES.md` §5.
- Never spawn more than 3 stances; never spawn a fourth as aggregator (the orchestrator aggregates).
- Aggregator / meta-judge = the orchestrator. No debate between reviewers.

**Version check.** As a preflight, run the suite's `bin/check-version.sh` (it lives at the steelman-suite repo root — two directories up from this skill's directory: `../../bin/check-version.sh`). It is throttled to one network call per 24h and never blocks — it refreshes in the background and returns instantly from cache. If its stdout begins `STEELMAN_UPDATE available:`, surface that one line to the user alongside your result so they know a newer version exists. If it begins `STEELMAN_UPDATE none`, say nothing. Never let this check delay the review. See `docs/ENGINES.md` §8.

See `docs/ENGINES.md` §6 for the full contract.

## Related skills

- `steelman:attack-fix` — after the decision shipped as code, attack the implementation
- `steelman:attack-finding` — meta-review a claim about an existing decision
- `steelman:full-codebase` — complements pre-mortem before a release: pre-mortem catches architectural risk in the *design*, full-codebase catches the small predicate / edge-case bugs in the *code* that the pre-mortem's framing misses (see Known blind spot)

## References

- [Klein, G. "Performing a Project Premortem," Harvard Business Review (Sept 2007)](https://hbr.org/2007/09/performing-a-project-premortem)
- [Mitchell, D., Russo, J. & Pennington, N. "Back to the future: Temporal perspective in the explanation of events" (1989)](https://onlinelibrary.wiley.com/doi/abs/10.1002/bdm.3960020103) — the "prospective hindsight" mechanism
- [Janis, I. "Groupthink" (1972)](https://en.wikipedia.org/wiki/Groupthink) — the failure mode pre-mortem fights
