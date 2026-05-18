---
name: steelman:full-codebase
description: Use this skill when the user wants a comprehensive adversarial pass on the ENTIRE repository — not a single commit or finding. Decomposes src/ by domain (parallel subagents per domain), spawns multi-AI jury per domain, aggregates into a single TRIAGE.md with severity-sorted findings. Use specifically when (a) the user asks "проверь весь код" / "audit the whole codebase" / «натрави на весь репо» / «full attack pass», (b) before a major release / merge to main, (c) after a long autonomous coding session and the user wants a safety sweep. Cost: ~30-60 minutes wall-clock, ~$5-20 in LLM costs. Use sparingly — for incremental review use attack-fix or devils-pair.
---

# steelman:full-codebase

> **Mandate:** Find every blocker in this codebase before it reaches production. Time-box: 60 min. Domain-parallel, MARS aggregation.

## Why this skill exists

Single-shot whole-repo reviews don't scale — codex (and Claude) blow context on a 60k-LOC repo and produce shallow generic findings. The fix is the same one production audit firms use: **domain decomposition**. Split the codebase into ≤5 functional domains, run independent reviewers per domain in parallel, then have a meta-reviewer consolidate.

This skill encodes that pattern + the SOTA-2026 design contract (heterogeneous jury per domain, strip-reasoning, tool-interactive verification, calibrated confidence).

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

### Step 2 — Spawn one `steelman:attack-fix`-style subagent per domain (parallel)

Each subagent receives:
- The list of files in its domain
- Mandate to apply `steelman:attack-fix` logic on the CURRENT HEAD (not a diff) — i.e. review all code as if it just landed
- The same anti-sycophancy / strip-reasoning / multi-AI-jury contract
- Time-box: 25 minutes per domain

Subagents run independently — **no cross-talk between domains** (MARS pattern).

Each writes to a per-domain file: `.steelman-cache/{run-id}/AUDIT-{domain}.md`.

### Step 3 — Aggregate (meta-reviewer pass)

After all domains return:
1. Read every per-domain audit
2. Deduplicate findings (same `file:line` from multiple domains → merge with combined confidence)
3. Rank by `(severity, calibrated_confidence, blast_radius)` lexicographic descending
4. Apply the **operator-binding contract check** from `steelman:attack-finding` — any finding contradicting a `CLAUDE.md` / `.planning/notes/` binding is reclassified `BY-DESIGN`
5. Apply the **reachability check** — flag-off / migration-applied / unreachable findings tagged `LATENT-NOT-FIRE`

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

3. **`codex exec` rate-limited mid-run** — Switch to dialectical-bootstrap for affected domains. Tag those domains' confidence as reduced.

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
- Optional pre-release CI gate: a GitHub Actions workflow that runs this on `release/*` branches (see [examples/ci-full-codebase-release-gate.yml](../../examples/ci-full-codebase-release-gate.yml))

## Related skills

- `steelman:attack-fix` — single-commit review (the building block this skill composes)
- `steelman:attack-finding` — meta-review of an existing claim
- `steelman:devils-pair` — fast smell-test on incremental changes

## References

- Field example: the 2026-05-18 ugolovkin run executed this pattern manually — 5 codex audits + 4 devils-advocate agents + 2 SOTA-research agents = 11 parallel agents over ~4 hours. Result: 14 confirmed-real fixes shipped to v2-dev (commits 429d93a4..36aab297), 32 findings triaged into latent/by-design buckets.
- [Sonar Foundation Agent (Nov 2025), 79.2% SWE-bench Verified](https://www.sonar.dev/blog/sonar-foundation-agent) — single-agent with great tools beats free-MAD on whole-repo; this skill applies the same lesson at the domain level (one strong agent per domain, no debate between them).
