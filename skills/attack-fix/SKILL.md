---
name: steelman:attack-fix
description: Use this skill when the user has a HIGH-BLAST-RADIUS code change (touching migrations / publish path / production data / security boundary) and wants formal adversarial review BEFORE deploying or merging. Spawns up to 3 reviewers (multi-AI jury — Claude + Codex + optional 3rd), strips implementer's reasoning trace, outputs each finding with steelman + counter + verifiable file:line + reproducible failing test. Wall-clock 5-10 min, cost ~$0.50-2. Use specifically when (a) the user explicitly says «attack my fix» / «devil's advocate this» / «разнеси мой фикс», (b) the diff touches `migrations/` / `src/main.py` / publish-stack / security gates, (c) the user is about to deploy AI-generated code without human review. Do NOT use for routine commits (use `steelman:devils-pair` — same logic, 60s, 2 reviewers). Do NOT use for style (use ruff/prettier).
---

# steelman:attack-fix

> **Mandate** (per Catholic Church 1587, Prussian Kriegsspiel 1812, CIA Team B 1976, Anthropic Orr 2026):
> Your job is to build the strongest case AGAINST this fix. Charity-of-interpretation is the enemy. If the fix looks correct, you have not looked hard enough.

## Inputs

The user invokes one of:
- `/steelman:attack-fix HEAD` — attack the most recent commit
- `/steelman:attack-fix <commit-hash>` — attack a specific commit
- `/steelman:attack-fix --staged` — attack the currently staged diff (pre-commit)
- `/steelman:attack-fix <path-to-patch-file>` — attack an arbitrary patch

If no argument: default to `HEAD`.

## Procedure

### Step 1 — Acquire the artifact (one-shot, mechanical)

```bash
REF="${1:-HEAD}"
case "$REF" in
  --staged)
    DIFF_TEXT="$(git diff --cached)"
    COMMIT_MSG="<staged, no commit message>"
    ;;
  *.patch|*.diff)
    DIFF_TEXT="$(cat "$REF")"
    COMMIT_MSG="<patch file>"
    ;;
  *)
    DIFF_TEXT="$(git show "$REF")"
    COMMIT_MSG="$(git log -1 --format='%s%n%n%b' "$REF")"
    ;;
esac
```

Store both. The diff goes to the jury STRIPPED. The commit message stays with YOU (Claude) for orchestration only — never passed to reviewers.

### Step 2 — Strip the implementer's reasoning trace

**This is the load-bearing counter-sycophancy step.** Per Anthropic Orr 2026, reviewers downgrade severity by 30%+ when given implementer framing (`9/10 Critical` redacted vs `6-7/10` framed).

Remove from the diff before passing to any reviewer:

1. **Commit message body** — never include "Codex audit caught X" or "Fixes bug Y". The reviewer must NOT know what the implementer believed they were fixing.
2. **Comments containing "I" / "we" / "the fix" / "to prevent" / "this addresses"** — neutralize to factual descriptions or delete.
3. **References to prior audits, ADRs, design docs** — the reviewer evaluates the code on its own merits, not its provenance.
4. **`# Codex review`, `# Audit finding`, `# Per operator`-style decorative comments** — strip.

What remains: pure code + minimal comments about WHAT the code does (never WHY it was added).

Use [`scripts/strip_reasoning.py`](scripts/strip_reasoning.py) for mechanical stripping, then read the output and confirm manually that no implementer narrative survives.

### Step 3 — Spawn heterogeneous jury (≥3 providers when available)

Per [Panel-of-LLM-Judges (Verga 2024)](https://arxiv.org/abs/2404.18796) + [Jury-on-Demand (2512.01786, 2025)](https://arxiv.org/abs/2512.01786) + [A-HMAD (2025)](https://arxiv.org/abs/2509.12054): a panel of **smaller heterogeneous models** beats a single large judge AND avoids intra-family correlated errors. **Same-family agreement is meaningless** (Refute-or-Promote 2024).

Spawn in parallel (independent contexts, **no cross-talk** — per MARS pattern):

| Reviewer | Model family | Tool used | Stance |
|---|---|---|---|
| Reviewer A | Anthropic (Claude Opus 4.7) | `Agent` tool, subagent | Senior security engineer who saw a previous version of this code break in production |
| Reviewer B | OpenAI (Codex GPT-5.5) | `Bash` → `codex exec` | Hostile reviewer at a competitor; wants to find anything to dunk on |
| Reviewer C | DeepSeek R1 OR Gemini 2.5 (if available) | Domain-specific (DeepSeek for cascade-heavy, Gemini for long-context) | Skeptical PhD reviewer evaluating for a top-tier venue |

If only 1 provider is reachable: fall back to **dialectical bootstrap** — two independent passes with the SAME model, fresh contexts, different temperatures (`T=0.0` and `T=0.8`), and adversarial role-priming. Per Herzog & Hertwig 2009 this captures ~50% of the gain from a true heterogeneous panel.

Each reviewer receives:
1. The stripped diff (Step 2 output)
2. The [reviewer prompt](references/reviewer-prompt.md) verbatim
3. NO commit message, NO design doc, NO prior audit context

### Step 4 — Per-reviewer output schema

Each reviewer must return findings in this exact shape:

```json
{
  "findings": [
    {
      "id": "F1",
      "verdict": "REAL|LIKELY-REAL|UNCLEAR|LIKELY-FALSE|FALSE",
      "file": "src/processing/article_processor.py",
      "lines": "956-961",
      "steelman": "The code attempts to gate 4c on the OR of four signals; this defends against the case where no alias matched but business keywords still indicate a business-criminal cluster.",
      "attack": "When matched_alias_tier == 'track_when_criminal' AND no criminal signal, has_business_keyword=True alone passes — contradicting the explicit D6 contract in CLAUDE.md.",
      "reproducible_test": "tests/processing/test_aliases_tier.py — add fixture: Лерчек + 'блогер запустил бизнес-курс' + is_criminal=False → expect filter_rejected at 4c. Currently passes 4c.",
      "execution_evidence": "grep -n 'has_business_keyword OR' src/processing/article_processor.py:956 → confirms current gate. Repro test would fail.",
      "blast_radius": "False-positive admissions of minor-public-figure articles into the digest pipeline. Operational cost: digest pollution, not data loss."
    }
  ],
  "no_findings_justification": null
}
```

`verdict` is categorical (REAL / LIKELY-REAL / UNCLEAR / LIKELY-FALSE / FALSE). v0.1 does not emit a numeric `confidence` — Brier-weighted aggregation is deferred to v0.3+ once enough run data accumulates. Reviewers pick one verdict; the meta-reviewer aggregates by majority.

**Findings missing `execution_evidence` are tagged `[UNVERIFIED]` in the aggregation step and deprioritized.** Per CodePRM / ThinkPRM 2025 pattern: claims without execution evidence are noise.

### Step 5 — Aggregate (MARS pattern, NOT free-for-all debate)

You (Claude orchestrator) play the **meta-reviewer** role per [MARS](https://arxiv.org/abs/2509.12054). No cross-talk between reviewers; each ran independently.

For each unique `(file, lines)` claim across reviewers:

| Reviewer votes | Aggregate verdict | Action |
|---|---|---|
| ≥2 reviewers REAL/LIKELY-REAL with `execution_evidence` | **CONFIRMED** | Surface to user, recommend block |
| 1 reviewer REAL + execution evidence | **NEEDS-OPERATOR** | Surface as borderline |
| ≥2 reviewers FALSE or no execution evidence | **DISMISSED** | Log internally, do not surface |
| Reviewers disagree sharply | **ESCALATED-DEBATE** | Trigger Step 6 (skip if 2-reviewer panel) |

v0.1 uses simple majority. **Brier-weighted aggregation and rolling calibration are v0.3 features** — deferred until enough run data accumulates to make calibration meaningful.

### Step 6 — Escalated debate (only when needed)

When reviewers disagree sharply on a finding, spawn a **structured 1-round debate**:

1. Reviewer A presents their attack
2. Reviewer B presents their defense (steelman of the code under attack)
3. A **fresh** meta-judge subagent (separate context, different model from A and B) reads both arguments + the stripped diff + executes any proposed reproducible_test, returns final verdict
4. NO further rounds — unbounded self-critique loops show diminishing returns above 2-3 turns (per multiple 2024-2025 studies)

### Step 7 — Output

Final report to the user with this structure:

```markdown
# Steelman attack on {commit/diff}

## Verdict
**CONFIRMED issues:** N
**Needs operator:** N
**Dismissed (false positives):** N

## Confirmed findings

### F1 — {short title} — {file}:{lines}
**Reviewer agreement:** 3/3 REAL (or 2/3 — note the dissenter)

**Steelman of the code:**
{quote}

**Attack:**
{quote}

**Reproducible failing test:**
{code block — operator can paste to verify}

**Execution evidence:**
{quoted output}

**Blast radius:**
{prose}

**Recommendation:**
{concrete, atomic — usually a small patch}

### F2 — ...

## Needs-operator-decision findings
{same shape, lower confidence}

## What we did NOT find
{explicit list — pre-empts confirmation bias on the operator's side}

## Methodology
- Reviewers: A=claude-opus-4-7, B=codex-gpt-5-5, C=deepseek-r1
- Reviewer prompt: [references/reviewer-prompt.md]
- Stripped reasoning trace: yes (per Anthropic Orr 2026)
- Cross-talk: no (MARS pattern)
- Tool-interactive verification: yes (claims without execution_evidence dropped)
- Aggregation: simple majority (Brier-weighted aggregate deferred to v0.3+)
```

## Failure modes you MUST handle

1. **All reviewers say "looks fine"** — Output "NO CONFIRMED ISSUES" but log to `evals/no-issue-attempts.jsonl`. Over time, if a fix that later breaks shows up here, your calibration is bad — flag for retraining.

2. **Only 1 provider reachable** — Drop to dialectical-bootstrap (Step 3 fallback). Tag the verdict `single-provider-bootstrap` so the operator knows confidence is reduced.

3. **`codex exec` times out** — Reduce the diff chunk size, retry once. If still failing, mark Reviewer B as `OFFLINE` and proceed with 2-reviewer panel; tag confidence as reduced.

4. **Diff is huge (>1k LOC)** — Decompose by file or by hunk. Run jury per-chunk. Aggregate. Per [Sonar Foundation Agent (Nov 2025)](https://www.sonar.dev/blog/sonar-foundation-agent-79-2-swe-bench-verified/), single-agent with great tools beats free-MAD on large changes — apply the same lesson here.

5. **No `git` repository / no diff available** — Refuse with a clear message; suggest the user run inside a git repo or provide a patch file.

6. **Reviewer claims a bug in dead code** — Reject the finding in Step 5 aggregation if `execution_evidence` shows the code path doesn't run (e.g. grep for callers returns zero).

## Anti-patterns to reject

- ❌ Single reviewer (same-family bias)
- ❌ Reviewer sees commit message or design doc (sycophancy)
- ❌ Free-for-all multi-agent debate (groupthink — per [_Stop Overvaluing MAD_, 2502.08788](https://arxiv.org/abs/2502.08788))
- ❌ Unbounded self-critique (>3 rounds)
- ❌ Claims without `execution_evidence` treated as findings
- ❌ Trailing praise / softening language ("Overall this is a strong fix, but...")
- ❌ Verdict before evidence (verdict-first writing order is for the FINAL report only; reasoning order is evidence-first)

## Auto-trigger conditions

This skill does **NOT** auto-trigger by default. Wall-clock 5-10 min + LLM cost makes it inappropriate as an ambient gate.

Use cases that justify firing:

- The user explicitly invokes `/steelman:attack-fix`
- The user's message contains `attack my`, `devil's advocate`, `разнеси`, AND a fresh `fix(...)` commit exists
- Operator-configured PreToolUse hook on `git push` ONLY when the staged diff touches a path in `STEELMAN_HIGH_BLAST_PATHS` env var (e.g. `migrations/`, `src/main.py`, `src/processing/article_processor.py`) — see [hooks/pre-commit-attack.sh](../../hooks/pre-commit-attack.sh) for the path-scoped opt-in pattern. Default = unconfigured = no hook fires.

For routine commits where the cost-benefit is wrong, use `steelman:devils-pair` (60s) or skip review entirely.

## Related skills

- `steelman:attack-finding` — meta-review of an existing audit finding (you have a bug report, want to know if it's real)
- `steelman:devils-pair` — lighter 2-agent quick check (mid-edit)
- `steelman:full-codebase` — orchestrator wrapping this skill across all changed files

## References

- [Reviewer prompt template](references/reviewer-prompt.md)
- [Strip-reasoning script](scripts/strip_reasoning.py)
- [Example output from ugolovkin audit 2026-05-18](../../examples/attack-my-fix-260518.md)

## Deferred to v0.3+

- Brier-weighted aggregation + rolling calibration (`references/calibration.md`)
- Minimax-ToT framing for individual reviewers (overhead too high for v0.1)
- Automatic provider-failover heuristics (manual fallback in v0.1)

## Inspiration

- Catholic [`advocatus diaboli`](https://en.wikipedia.org/wiki/Advocatus_Diaboli) (1587-1983)
- [CriticGPT (McAleese 2024)](https://arxiv.org/abs/2407.00215) — 85% bug catch vs 25% unaided
- [PoLL (Verga 2024)](https://arxiv.org/abs/2404.18796) — heterogeneous jury beats single judge
- [MARS (2025)](https://arxiv.org/abs/2509.12054) — independent reviewers + meta-reviewer, no cross-talk
- [Anthropic Orr 2026](#) — strip implementer's reasoning trace before review
- Field-tested 2026-05-18 on [ooookaaay/ugolovkin](https://github.com/ooookaaay/ugolovkin) — caught two real regressions in shipped fixes before they hit prod
