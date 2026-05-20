---
name: steelman:full-codebase
description: Use when you want a thorough adversarial pass on the ENTIRE codebase — not a single commit or claim. The skill splits `src/` into ≤5 functional domains (by LOC and topical cohesion), runs an independent reviewer per domain in parallel, then aggregates into one TRIAGE.md sorted by severity. Each reviewer applies the same attack-fix discipline (anti-sycophancy, strip-reasoning, file:line evidence) but scoped to its domain. 30-60 min wall-clock, ~$5-20. Triggers: «проверь весь код», «audit the whole codebase», «натрави на весь репо», «full attack pass», before a major release or merge to main, after a long autonomous coding session when you want a safety sweep. Use sparingly — for incremental review go through `attack-fix` or `devils-pair`.
---

# steelman:full-codebase

> **Mandate:** Find every blocker in this codebase before it reaches production. Time-box: 60 min. Domain-parallel, isolated reviewers, aggregator-merged.

## Why this skill exists

Single-shot whole-repo reviews don't scale. Codex (and Claude) blow context on a 60k-LOC repo and produce shallow generic findings — «consider adding error handling here», «this could be more Pythonic» — because they can't hold enough of the codebase in working memory to spot real architecture-level bugs.

The fix is the same one production audit firms have used for a century: **domain decomposition**. Split the codebase into ≤5 functional domains (storage, publish, processing, etc), run one focused reviewer per domain in parallel, then have an aggregator merge results. Each reviewer holds its slice in working memory; the aggregator only has to merge findings, not re-derive them.

This skill encodes that pattern plus the suite's design contract: heterogeneous jury per domain (different model families), strip the implementer's reasoning trace, tool-interactive verification (every claim grounded by `Read` / `grep` / running code), calibrated confidence. Reviewers run in isolation — they can't see each other's findings during the review — so they can't anchor on each other's wrong conclusions. This is the **MARS pattern** (Multi-Agent Reviewers in Separation), and it consistently outperforms free-for-all multi-agent debate.

Field example: the 2026-05-18 ugolovkin audit cycle ran this pattern manually (5 parallel codex audits across cascade / publish / storage / orchestration / eval-ingestion). Found ~149 issues, 47 HIGH. 14 confirmed-real after triage. **This skill automates that pattern.**

## Inputs

```bash
/steelman:full-codebase                          # auto-detect domains, ≤5 parallel
/steelman:full-codebase --domains a,b,c          # explicit domain list (paths)
/steelman:full-codebase --since HEAD~50          # only files changed in last 50 commits
/steelman:full-codebase --quick                  # devils-pair per domain instead of attack-fix (~10 min)
```

## Procedure

### Step 1 — Detect domains

Auto-decompose `src/` (or the project's primary code dir):

```bash
# Heuristic: any subdirectory with ≥500 LOC is its own domain.
# Files at src/ root group by topical clusters (NER → ner_domain, etc).
DOMAINS=$(find src -mindepth 1 -maxdepth 2 -type d | \
  while read d; do
    loc=$(find "$d" -name '*.py' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
    [ "${loc:-0}" -ge 500 ] && echo "$d:$loc"
  done | sort -t: -k2 -n -r | head -5)
```

If fewer than 5 domains, just use what's there. If more than 5, group the smallest ones together until you have ≤5 (keeps parallel-agent budget bounded).

If the user provides `--domains`, skip auto-detection.

### Step 2 — Spawn reviewers per domain (parallel)

**Domain pre-gate:** with `--since`, compute which files in each domain changed. Domains with zero changed files are skipped entirely — no reviewer is spawned for them.

For each remaining domain, spawn **two parallel reviewers in isolation** (MARS pattern, no cross-talk between domains):

- **Reviewer A (Claude):** Agent-tool subagent scoped to the domain's file list. Applies `steelman:attack-fix` attack discipline on CURRENT HEAD (code treated as if it just landed). Never use `claude -p`. Time-box: 25 minutes.
- **Reviewer B (Codex):** `codex exec` call over the domain's file list (see `docs/ENGINES.md` §4b for invocation recipe). Same attack discipline, independent context.

**Codex absent:** both A and B are Agent-tool Claude subagents for that domain, with distinct adversarial stances. Emit the honest single-provider label from `docs/ENGINES.md` §5 in the per-domain audit header.

Each domain pair writes findings to: `.steelman-cache/{run-id}/AUDIT-{domain}.md`.

**The +1 cross-family verifier runs ONCE at Step 3 aggregation** over the merged HIGH findings — not per domain. Do not spawn a verifier per domain.

### Step 3 — Aggregate (meta-reviewer pass + one cross-family verifier)

After all domains return:
1. Read every per-domain audit
2. Deduplicate findings (same `file:line` from multiple domains → merge with combined confidence)
3. Rank by `(severity, calibrated_confidence, blast_radius)` lexicographic descending
4. Apply the **operator-binding contract check** from `steelman:attack-finding` — any finding contradicting a `CLAUDE.md` / `.planning/notes/` binding is reclassified `BY-DESIGN`
5. Apply the **reachability check** — flag-off / migration-applied / unreachable findings tagged `LATENT-NOT-FIRE`
6. **+1 cross-family verifier pass (once, here):** run one `codex exec` call (or, Codex absent, one additional Claude Agent-tool subagent) over the merged HIGH findings only — auditing the *jury's findings*, not the code. This is the Tier-3 +1 verifier from `docs/ENGINES.md` §3, applied once at aggregation. Do not re-run it per domain.

### Step 4 — Output single TRIAGE.md

```markdown
# Steelman Full-Codebase Pass — {timestamp}

## Summary
- Domains audited: {N}
- Total findings: {N}
- CONFIRMED-REAL (HIGH severity): {N}
- LATENT-NOT-FIRE: {N}
- BY-DESIGN (per operator binding): {N}
- FALSE-POSITIVE: {N}
- NEEDS-OPERATOR-INPUT: {N}

## CONFIRMED-REAL (HIGH severity) — fix these first

### F1 — {title} — {file:line}
{full attack-fix output schema}

### F2 — ...

## CONFIRMED-REAL (MEDIUM)
...

## LATENT-NOT-FIRE — keep in backlog with re-evaluation trigger

### L1 — {title} — {file:line}
Reachability gate: {what blocks reachability}
Re-evaluate when: {trigger condition}

## BY-DESIGN — retire from any backlog

### D1 — {title} — {file:line}
Binding: {file:line of binding contract}
Quote: "{relevant text}"

## NEEDS-OPERATOR-INPUT

### O1 — {title}
Question: {1 sentence}

## Per-domain audits
- [.steelman-cache/{run-id}/AUDIT-cascade.md]
- [.steelman-cache/{run-id}/AUDIT-publish.md]
- ...

## Methodology
- Domains: {list with LOC counts}
- Parallel subagents: {N}
- Wall-clock: {N} min
- LLM cost estimate: ${N}
- Reviewer rotation: {which models per domain}
- Strip-reasoning: yes
- Cross-talk between domains: no (MARS)
- Operator-binding contract checked: ✓
- Reachability checked: ✓
- Calibrated confidence: yes (Brier-weighted)
```

### Step 5 — Optional: emit a fix-plan

If `--with-fix-plan` is passed, after the TRIAGE.md, also generate `.steelman-cache/{run-id}/FIX-PLAN.md` ordering CONFIRMED-REAL findings by `cost / blast_radius` (cheapest, highest-blast-radius first). The operator can then iterate per finding with `steelman:attack-fix` to verify the fix.

## Failure modes

1. **Domain auto-detect picks 0 domains** — Fall back to single-domain review on the entire src/. Tag confidence as reduced (single-agent risk).

2. **One domain's subagent crashes** — Retry once with smaller chunk. If still failing, mark domain as `INCOMPLETE` in the final report; do NOT block the other domains.

3. **`codex exec` rate-limited or unavailable mid-run** — Switch to the Codex-absent path for affected domains (two Agent-tool Claude subagents with distinct stances). Emit the honest single-provider label from `docs/ENGINES.md` §5 in those domains' audit headers. Tag their confidence as reduced.

4. **Cost budget exceeded** — Estimate from per-domain LOC. If projected to exceed `STEELMAN_BUDGET_USD` env var, abort and ask the user to either raise the budget or pass `--quick`.

## Cost estimation

| Project size | Typical cost | Typical wall-clock |
|---|---|---|
| <10k LOC | $1-3 | 10-15 min |
| 10-50k LOC | $3-10 | 20-40 min |
| 50-100k LOC | $10-25 | 40-60 min |
| >100k LOC | $20+ | use `--quick` or scope to changed files only |

Cost approximations assume 3-model jury (Claude Opus + Codex GPT-5.5 + DeepSeek R1). Reduce by passing `--quick` (devils-pair per domain instead of full attack-fix jury).

## Auto-trigger conditions

This skill does **not** auto-trigger by default. It's expensive ($5-20) and slow (30-60 min) — false-firing wastes operator time and credits.

Manual invocation only:
- `/steelman:full-codebase`
- Optional pre-release CI gate: wire a GitHub Actions workflow that runs this on `release/*` branches.

## Engine routing

**Tier 3 per domain.**

- **Domain pre-gate:** with `--since`, domains with no changed files are skipped entirely — zero reviewer cost for them.
- **Codex present:** per domain, one Claude Agent-tool subagent (Reviewer A) + one `codex exec` call (Reviewer B) run in parallel. No cross-talk between domains or between reviewers (MARS).
- **Codex absent:** per domain, two Agent-tool Claude subagents with distinct adversarial stances. Emit the honest single-provider label from `docs/ENGINES.md` §5 in each affected domain's audit header.
- **+1 verifier:** one `codex exec` call (or orchestrator when Codex absent) runs once at Step 3 aggregation over the merged HIGH findings — not per domain.
- Aggregator / meta-judge = the orchestrator. Never spawn a reviewer as aggregator.

See `docs/ENGINES.md` §6 for the full contract.

## Related skills

- `steelman:attack-fix` — single-commit review (the building block this skill composes)
- `steelman:attack-finding` — meta-review of an existing claim
- `steelman:devils-pair` — fast smell-test on incremental changes
- `steelman:pre-mortem` — run on a *design* before commitment; `full-codebase` then catches the predicate / edge-case bugs in the *implementation* that a pre-mortem's framing misses. The two are complementary — run both before a milestone tag, not one instead of the other.

## References

- Field example: the 2026-05-18 ugolovkin run executed this pattern manually — 5 codex audits + 4 devils-advocate agents + 2 background-research agents = 11 parallel agents over ~4 hours. Result: 14 confirmed-real fixes shipped to v2-dev (commits 429d93a4..36aab297), 32 findings triaged into latent/by-design buckets.
- Field example: the 2026-05-19 ugolovkin v2.15 release-gate run (`v2.15-fullpass-20260519T1730`) — 5 domains, ~55k LOC, 38 min, 5 parallel agents. 8 confirmed-real HIGH. Caught **D-F1**, a whitespace-fragile predicate in a hotfix that had shipped to production the same day — a bug a design `pre-mortem` had missed because its attention was on the rule's architecture, not on string-equality details. Fixed in-session, hours before the publish deadline. This run is the field basis for the «pre-mortem and full-codebase are complementary» note in `steelman:pre-mortem`.
- [Sonar Foundation Agent (Nov 2025), 79.2% SWE-bench Verified](https://www.sonar.dev/blog/sonar-foundation-agent) — single-agent with great tools beats free-MAD on whole-repo; this skill applies the same lesson at the domain level (one strong agent per domain, no debate between them).
