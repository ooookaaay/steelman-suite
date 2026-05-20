---
name: steelman:devils-pair
description: Use when you've staged a small code change (≤200 LOC) and want a fast cross-AI sanity check before commit or push. Two reviewers — one same-family, one cross-family — each return a one-paragraph verdict in ≤60 seconds. Smell-test, not a deep review. Triggers: «быстро проверь», «devils pair», «quick adversarial check», before `git push` on a small change, the user wants ~1 minute of cross-AI safety over zero. NOT a substitute for `attack-fix` on high-blast-radius changes — findings here have weaker confidence than attack-fix, treat as «smell test passed» not «verified safe».
---

# steelman:devils-pair

> **Mandate:** Find ONE concrete reason to block this change in 60 seconds. Time-boxed, evidence-required.

## Why this skill exists

`steelman:attack-fix` takes 5-10 minutes wall-clock (3-reviewer jury + tool-interactive verification + aggregation). For an 8-line change to a logging statement, that's overkill. But zero adversarial review is too little — same-family LLM coding assistants share blind spots and tend to agree with the framing they were given.

`devils-pair` is the **fastest non-trivial adversarial review** that still has cross-family safety. The two reviewers run in isolation — see results, not each other's reasoning — so they can't anchor to the same wrong conclusion. It's a smell-test, not a deep review.

## Inputs

```bash
/steelman:devils-pair                  # attack staged diff
/steelman:devils-pair --commit HEAD    # attack the most recent commit
/steelman:devils-pair --range a..b     # attack a commit range
```

The skill expects the diff to be ≤200 LOC. For larger diffs, it refuses and points to `steelman:attack-fix`.

## Procedure

### Step 0 — Static pre-gate (free, runs first)

Before any model call, compute from change metadata:

```bash
LOC_CHANGED=$(git diff --cached --numstat 2>/dev/null | awk '{a+=$1+$2} END {print a+0}')
FILES_CHANGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
```

If `LOC_CHANGED ≤ 25` AND `FILES_CHANGED ≤ 2` AND no high-blast path is touched (see `STEELMAN_HIGH_BLAST_PATHS`), the change is **Tier 0 — skip**: say so and exit without spawning reviewers.

If any high-blast path is touched, do not run `devils-pair` — recommend `attack-fix` (high-blast changes are always Tier 3).

### Step 1 — Acquire and bound

```bash
DIFF="$(git diff --cached || git show HEAD)"
LINES_CHANGED=$(echo "$DIFF" | wc -l)
if [ "$LINES_CHANGED" -gt 200 ]; then
  echo "Diff too large ($LINES_CHANGED LOC) for devils-pair. Use /steelman:attack-fix for a thorough review."
  exit 1
fi
```

### Step 2 — Strip reasoning (essentials only)

For a quick review, strip just the bare minimum:
- Commit message (don't pass)
- Comment lines starting with `# Codex` / `# Audit` / `# Per operator` / `# Fix:`

Keep regular code comments — too aggressive a strip for a quick check would lose useful context the reviewer needs to even understand what's going on.

### Step 3 — Spawn 2 reviewers in parallel (single message, no cross-talk)

**Reviewer A — Claude (Agent-tool subagent, murder-board stance):**
- Spawned via the `Agent` tool (fresh isolated context, model=opus). Never use `claude -p` — nested calls return empty.
- Stance: «murder-board: hostile senior engineer, breaks confidence, ≤200 words»
- Prompt: pass the stripped diff + ask for ONE concrete blocker

**Reviewer B — Codex (cross-family, hostile-competitor stance):**
- Invoked via `codex exec` Bash call (separate process). Use the invocation recipe in `docs/ENGINES.md` §4b with `--skip-git-repo-check`.
- Stance: «adversarial reviewer at a hostile competitor, ≤200 words»
- Same payload

**Codex absent:** both A and B become Agent-tool Claude subagents with distinct adversarial stances (murder-board and hostile-competitor). This provides context isolation and adversarial framing but shares architectural blind spots — the honest single-provider label from `docs/ENGINES.md` §5 must appear in the output.

Time-box: 60 seconds. If a reviewer hasn't returned, mark `TIMEOUT` and proceed with the one that did.

### Step 4 — Aggregate (no debate, no jury)

Pair logic is simpler than the full jury:

| Reviewer A | Reviewer B | Verdict |
|---|---|---|
| ✓ finds concrete blocker | ✓ finds concrete blocker | **BLOCK** — surface both findings |
| ✓ finds blocker | "looks fine" | **NEEDS-ATTENTION** — surface A's finding, note cross-family disagreement |
| "looks fine" | ✓ finds blocker | **NEEDS-ATTENTION** — surface B's finding, note cross-family disagreement |
| "looks fine" | "looks fine" | **PAIR-PASSED** — smell-test cleared, NOT verified safe |
| ✓ finds blocker | TIMEOUT | **NEEDS-ATTENTION** + degraded confidence tag |
| TIMEOUT | TIMEOUT | **FAILED — cannot proceed**; suggest manual review or attack-fix |

**Confidence tag** in output: `pair-confidence-medium` — communicates that this is a screen, not a verified-safe verdict. The operator should NOT use this as the final go-no-go for high-blast-radius changes (deploys to prod, dropping tables, etc).

### Step 5 — Output (≤1 screen)

```markdown
# Devils-pair on {diff}

**Verdict:** {BLOCK | NEEDS-ATTENTION | PAIR-PASSED | FAILED}
**Confidence:** pair-confidence-medium
**Wall-clock:** {N}s
**Reviewers:** A=claude (same-family), B=codex (cross-family)

## Reviewer A
{paragraph}

## Reviewer B
{paragraph}

## Recommendation
{1 sentence}

---
*This is a smell-test, not a thorough review. For high-blast-radius changes, escalate to /steelman:attack-fix.*
```

## When to use this vs attack-fix

| Scenario | Use |
|---|---|
| ≤50 LOC change, low blast-radius | `devils-pair` |
| Logging / docs / formatting changes | `devils-pair` (or skip) |
| Test-only changes | `devils-pair` |
| Pre-`git push` quick gate | `devils-pair` |
| Logic change in hot path | `attack-fix` |
| Anything touching prod data / migrations / publication | `attack-fix` |
| Security-sensitive change | `attack-fix` |
| Anything you're not 100% sure about | `attack-fix` |

## Failure modes

1. **Codex unavailable** — Fall back to two Agent-tool Claude subagents with distinct stances (murder-board + hostile-competitor). Emit the honest single-provider label from `docs/ENGINES.md` §5 in the output header. Do NOT refuse — the bootstrap path is valid.

2. **Reviewers disagree sharply** — Don't run a debate (defeats the time-box). Output `NEEDS-ATTENTION` and recommend escalating to `attack-fix` for a full Tier-3 jury. Do not attempt to resolve disagreement within this skill.

3. **Diff is non-code** (markdown / yaml / json) — Run anyway. Adversarial review of YAML configs / prompts is sometimes more valuable than code review.

## Auto-trigger conditions

This skill auto-triggers when:

- A `PostToolUse Edit|Write` hook fires with cumulative ≥5 lines changed (see [hooks/post-fix-pair.sh](../../hooks/post-fix-pair.sh)) — the simplest, lowest-friction adversarial gate
- The user runs `git diff --cached` and then says «commit?» / «ok?» / «гоу»
- The user explicitly invokes `/steelman:devils-pair`

## Engine routing

**Tier 2 — pair.**

- **Static pre-gate first** (Step 0 above): Tier-0 change → exit immediately, no reviewers spawned. High-blast path → refuse, redirect to `attack-fix`.
- **Codex present:** Reviewer A = Claude Agent-tool subagent (murder-board stance); Reviewer B = `codex exec` (hostile-competitor stance). Both run in parallel, isolated — MARS pattern.
- **Codex absent:** both A and B are Agent-tool Claude subagents with distinct stances. Context isolation and adversarial framing are preserved; same-family architectural blind spots are not. Emit the honest single-provider label from `docs/ENGINES.md` §5.
- **On disagreement:** do not debate, do not escalate inside this skill. Surface `NEEDS-ATTENTION` and recommend `attack-fix` for Tier-3 resolution.
- No early-exit rule needed — only two reviewers; the pair result is always final for this skill.

See `docs/ENGINES.md` for the full contract.

## Related skills

- `steelman:attack-fix` — thorough review (5-10 min, ≥3 reviewers, tool-interactive verification)
- `steelman:attack-finding` — when you have a claim about existing code, not a fresh diff

## References

- [Refute-or-Promote, 2024](https://arxiv.org/abs/2406.00374) — same-family agreement is meaningless; cross-family is the load-bearing pair
- [Cohere LLM-Jury, 2024](https://arxiv.org/abs/2404.18796) — 2-judge panel already beats single-judge at much lower cost
- Field-tested example: in the ugolovkin 2026-05-18 audit cycle, the pair-style cross-AI check (DA #1 Claude + DA #3 Codex) **independently flagged the same 3 regressions** in 3 of 5 highest-priority concerns — pair design works in practice
