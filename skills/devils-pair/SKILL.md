---
name: steelman:devils-pair
description: Use this skill when the user wants a fast adversarial sanity check on a small code change mid-edit BEFORE running the full attack-fix pipeline. Spawns exactly 2 reviewers — same-family and cross-family — in parallel, each returning a one-paragraph verdict in ≤60 seconds wall-clock. Use specifically when (a) the user has staged a small change and wants quick "good to commit?" cross-AI check, (b) before a `git push` and the user wants ~1 minute of cross-AI safety over zero, (c) the user explicitly says «быстро проверь» / «devils pair» / «quick adversarial check». Do NOT use as a substitute for full attack-fix — this is a screen, not a thorough review. Findings here are weaker confidence than attack-fix and should be treated as «smell test passed» not «verified safe».
---

# steelman:devils-pair

> **Mandate:** Find ONE concrete reason to block this change in 60 seconds. Time-boxed, evidence-required.

## Why this skill exists

`steelman:attack-fix` takes 5-10 minutes wall-clock (3-reviewer jury + tool-interactive verification + aggregation). For an 8-line change to a logging statement, that's overkill. But zero adversarial review is too little — same-family LLM coding assistants are systemically sycophantic.

`devils-pair` is the **fastest non-trivial adversarial review** that still has cross-family safety. It's a smell-test, not a deep review.

## Inputs

```bash
/steelman:devils-pair                  # attack staged diff
/steelman:devils-pair --commit HEAD    # attack the most recent commit
/steelman:devils-pair --range a..b     # attack a commit range
```

The skill expects the diff to be ≤200 LOC. For larger diffs, it refuses and points to `steelman:attack-fix`.

## Procedure

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

**Reviewer A — same family (Claude):**
- Subagent via `Agent` tool, `general-purpose` type, model=opus
- Stance: «hostile senior engineer, breaks confidence, ≤200 words»
- Prompt: pass the stripped diff + ask for ONE concrete blocker

**Reviewer B — cross-family (Codex):**
- `codex exec --skip-git-repo-check` synchronous
- Stance: «adversarial reviewer at competitor, ≤200 words»
- Same payload

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

1. **Only 1 reviewer available** — Skill refuses. Pair requires cross-family by definition. Suggest `attack-fix` (which has dialectical-bootstrap fallback) or manual review.

2. **Reviewers disagree sharply** — Don't run a debate (defeats the time-box). Output `NEEDS-ATTENTION` and let the operator decide whether to escalate to `attack-fix`.

3. **Diff is non-code** (markdown / yaml / json) — Run anyway. Adversarial review of YAML configs / prompts is sometimes more valuable than code review.

## Auto-trigger conditions

This skill auto-triggers when:

- A `PostToolUse Edit|Write` hook fires with cumulative ≥5 lines changed (see [hooks/post-fix-pair.sh](../../hooks/post-fix-pair.sh)) — the simplest, lowest-friction adversarial gate
- The user runs `git diff --cached` and then says «commit?» / «ok?» / «гоу»
- The user explicitly invokes `/steelman:devils-pair`

## Related skills

- `steelman:attack-fix` — thorough review (5-10 min, ≥3 reviewers, tool-interactive verification)
- `steelman:attack-finding` — when you have a claim about existing code, not a fresh diff

## References

- [Refute-or-Promote, 2024](https://arxiv.org/abs/2406.00374) — same-family agreement is meaningless; cross-family is the load-bearing pair
- [Cohere LLM-Jury, 2024](https://arxiv.org/abs/2404.18796) — 2-judge panel already beats single-judge at much lower cost
- Field-tested example: in the ugolovkin 2026-05-18 audit cycle, the pair-style cross-AI check (DA #1 Claude + DA #3 Codex) **independently flagged the same 3 regressions** in 3 of 5 highest-priority concerns — pair design works in practice
