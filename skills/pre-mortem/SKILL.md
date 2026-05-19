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

### Step 2 — Spawn pre-mortem jury (≥3 reviewers, parallel, MARS pattern)

Each reviewer takes a different stance to expand the failure-mode coverage:

| Reviewer | Stance | Mandate |
|---|---|---|
| **The senior engineer who joined six months ago** | Knows the codebase, hasn't drunk the kool-aid on this decision | "Tell me the technical failure modes — what does this break that the team hasn't thought about?" |
| **The on-call who got paged** | Was at the wrong end of this failure mode | "Walk me through the page-to-resolution. What was the symptom? What was the root cause? Why did it take so long to figure out?" |
| **The skeptic external advisor** | No skin in the game | "Why is this decision wrong? Argue from first principles." |

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

## Auto-trigger conditions

- The user's message contains «pre-mortem» / «premortem» / «failure modes» / «что может сломаться»
- The user says «давай делать X» / «let's go with X» AND no prior pre-mortem was run for X
- A `phase-spec` / `decision-doc` / ADR markdown file is being written or committed AND no companion `pre-mortem.md` exists yet

## Related skills

- `steelman:attack-fix` — after the decision shipped as code, attack the implementation
- `steelman:attack-finding` — meta-review a claim about an existing decision

## References

- [Klein, G. "Performing a Project Premortem," Harvard Business Review (Sept 2007)](https://hbr.org/2007/09/performing-a-project-premortem)
- [Mitchell, D., Russo, J. & Pennington, N. "Back to the future: Temporal perspective in the explanation of events" (1989)](https://onlinelibrary.wiley.com/doi/abs/10.1002/bdm.3960020103) — the "prospective hindsight" mechanism
- [Janis, I. "Groupthink" (1972)](https://en.wikipedia.org/wiki/Groupthink) — the failure mode pre-mortem fights
