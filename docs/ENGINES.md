# Engine routing & efficiency contract

> How every steelman skill decides **which engines to call** and **whether a
> review is worth running at all**. One contract, referenced by all six skills.
>
> Design goal: a genuine cross-model jury when it matters — and **zero wasted
> time on changes that don't need one**. Efficiency is the spine, not a flag.

---

## 1. The problem this fixes

steelman skills are SKILL.md prose executed by an AI agent. The agent's
subagent spawner produces **same-family (Claude) subagents only**. A second
model family (OpenAI Codex) enters **only** via an explicit `codex exec` Bash
call. Earlier versions described a "multi-AI jury" in prose but shipped no
mechanism — so runs silently degraded to one model family. This contract
replaces the prose with a concrete, efficiency-gated procedure.

Two hard rules:

1. **Never use `claude -p` inside a skill.** A nested `claude -p` launched from
   inside a running session returns empty output the majority of the time
   (measured: 78/110 runs). The Claude reviewer is always an **Agent-tool
   subagent**. `codex exec` (a separate process) is unaffected and is the
   correct way to reach Codex.
2. **Decide the tier before spending a token.** The skip / single / pair / jury
   decision is made from **static change metadata** — no LLM call. A
   pre-generation static classifier beats LLM-confidence cascades on most
   benchmarks (arXiv:2605.06350) and costs nothing.

---

## 2. The efficiency spine

```
  STATIC PRE-GATE   →   TIER   →   DISAGREEMENT-GATED ESCALATION   →   EARLY EXIT
  (zero LLM, ~0ms)      (0-3)      (escalate only when inconclusive)   (stop at quorum)
```

### 2a. Static pre-gate — free, runs first, always

Compute from the diff / change scope, no model call:

| Signal | Source |
|--------|--------|
| Lines changed (added + deleted) | `git diff --numstat` |
| Distinct files touched | `git diff --name-only` |
| Blast-radius path hit | match changed paths against the high-blast set¹ |
| (optional) cyclomatic-complexity delta | static analyzer if available |

¹ High-blast set = migrations / schema, auth, the publish/release path,
security-sensitive code, CI config. Operator-configurable via the
`STEELMAN_HIGH_BLAST_PATHS` env var (space-separated path prefixes). A change
touching ANY high-blast path is never Tier 0 or Tier 1 — it jumps to Tier 3.

These signals predict "needs deep review" with production-validated accuracy
(AUC 0.96 over 131K reviews — arXiv:2601.00753). They are static and
zero-latency, so the gate is effectively free.

### 2b. Tiers

| Tier | When (static signals) | Engines | Cost |
|------|----------------------|---------|------|
| **0 — skip** | ≤ ~25 LOC, ≤ 2 files, no high-blast path | none | $0 / 0s |
| **1 — single** | ≤ ~100 LOC, no high-blast path | 1 context-isolated Claude reviewer | ~$0.03 |
| **2 — pair** | > ~100 LOC, or multi-file, or moderate risk | Claude + Codex (cross-family) | ~$0.05-0.20 |
| **3 — jury + verifier** | any high-blast path, or very large diff | 3 reviewers + 1 cross-family verifier | ~$0.50-2 |

Thresholds are defaults — operator-tunable via env vars
(`STEELMAN_TIER1_MAX_LOC`, `STEELMAN_TIER0_MAX_LOC`). The numbers come from the
100-line review boundary in production review data; treat them as a starting
calibration, not physics.

### 2c. Disagreement-gated escalation — the "right moment" mechanism

You do **not** pre-pay for the highest tier. You run the tier the pre-gate
chose, then escalate **only if the cheap pass was inconclusive**:

- **Tier 1 → 2:** the single reviewer raises a non-trivial finding → add a
  cross-family second opinion before believing or dismissing it.
- **Tier 2 → 3:** the two reviewers **disagree** (one BLOCK, one PASS) → add the
  third reviewer + meta-judge. If they **agree** (both PASS, or both BLOCK the
  same thing) → **done, do not escalate.**

Inter-reviewer disagreement is the best escalation signal for a 2-reviewer
system — no confidence calibration needed, and it escalates on only ~3-4% of
changes in practice (DREAM, arXiv:2602.06526: 95.2% accuracy at 3.5%
escalation). This is what keeps the suite out of the way.

### 2d. Early exit — stop at quorum

Within a Tier-3 jury: if the first two reviewers return **decisively unanimous**
verdicts (both PASS with concrete ruled-out vectors, or both BLOCK the same
`file:line`), the third reviewer and meta-judge add nothing — skip them.
Quorum-based early termination saves 19-55% of cost at <0.2% quality loss
(arXiv:2601.05777). Only run the full jury when the first two leave the verdict
open.

---

## 3. Engine roles

| Role | Realised as | Never |
|------|-------------|-------|
| **Claude reviewer** | an Agent-tool subagent (fresh context, stripped framing) | `claude -p` (nested → empty) |
| **Codex reviewer** | `codex exec` via Bash (separate process) | — |
| **Aggregator / meta-judge** | the orchestrator agent itself | a spawned reviewer (breaks MARS) |

All reviewers run **in parallel, in isolation** — MARS pattern (Multi-Agent
Reviewers in Separation): no reviewer sees another's output; the aggregator
merges. Independent + merge matches debate accuracy at ~50% fewer tokens
(arXiv:2509.20502; "Stop Overvaluing MAD" arXiv:2502.08788).

**Jury size:** 3 is the empirical sweet spot — k=1→3 buys +6.7pp accuracy,
k=3→8 buys only +3.1pp at 2.7× cost (arXiv:2604.13717). Never run more than 3
generators. **Aggregation:** 2-of-3 majority for findings; unanimity (AND) only
for hard kill-switch / block decisions.

**The +1 verifier (Tier 3 only):** after the jury, one cross-family reviewer
audits the *jury's findings* (not the code). This 3-generators + 1-adversarial-
verifier pattern added +10.3pp precision and −31.5pp false-positives in code
vulnerability detection (arXiv:2604.21282). In steelman this is the meta-judge
running on Codex when Codex is available.

---

## 4. Calling Codex — detection and invocation

### 4a. Detect — before relying on it

`codex` may be installed but unauthenticated. Probe all three:

```bash
codex_usable() {
  command -v codex >/dev/null 2>&1 || return 1
  codex --version  >/dev/null 2>&1 || return 1
  [ -n "${CODEX_API_KEY:-}" ] && return 0
  [ -f "$HOME/.codex/auth.json" ] && grep -q refresh_token "$HOME/.codex/auth.json" && return 0
  return 1
}
```

If this fails, OR a `codex exec` call exits non-zero / returns empty → treat
Codex as unavailable for this run and use the bootstrap fallback (§5).

### 4b. Invoke — review mode

```bash
timeout --kill-after=5s "${STEELMAN_CODEX_TIMEOUT:-180}s" \
  codex exec --sandbox read-only --skip-git-repo-check --ephemeral \
  -o "$RUN_DIR/codex-review.txt" - <<'PROMPT'
<the reviewer prompt + stripped diff/code here>
PROMPT
```

- **`-o/--output-last-message <FILE>`** — the reliable way to capture the final
  answer. Default stdout also carries only the final message, but `--json`
  schema drifts between versions — prefer `-o`.
- **`codex exec -`** reads the prompt from stdin — use it; long prompts overflow
  shell arg limits.
- **`--sandbox read-only`** for pure review (reviewer reads files, runs grep);
  `workspace-write` only if the reviewer must run tests.
- **`timeout` wrapper** — `codex exec` has no built-in timeout. Exit 124 = timed
  out → treat as a degraded reviewer, do not block on it.
- Parallel `codex exec` calls are safe (stateless) but share one rolling quota
  window — do not fan out more than the tier needs.

---

## 5. Codex absent — dialectical bootstrap (honest fallback)

When Codex is not usable, reviewer B (and C) become **additional Agent-tool
Claude subagents**, each in a fresh isolated context with a *different*
adversarial stance (see each skill's stance list).

This is **not** equivalent to a cross-family jury and must not be sold as one.
What it recovers (validated): context isolation and adversarial framing — the
two interventions that actually cut sycophantic review (arXiv:2603.12123:
+4 F1 / +11pp on critical errors from a fresh isolated session; adversarial
framing worth 16-93% of detection). What it cannot recover: same-family models
share architectural blind spots (+6.6-7.6pp correlated error rate —
arXiv:2506.07962).

**Honest label, emitted in every bootstrap-mode report:**

> Single-provider mode — reviewers are context-isolated Claude passes with
> distinct adversarial stances. This catches in-session sycophancy but shares
> architectural blind spots a cross-family jury would not. Roughly half the
> assurance of a Claude+Codex jury. Install and authenticate `codex` for the
> full contract.

Do not run the same model in a multi-turn debate as a substitute — multi-turn
review raises false positives ~62% (arXiv:2603.16244) and same-model debate
inflates confidence without accuracy (arXiv:2505.19184).

---

## 6. Per-skill mapping

| Skill | Tier | Reviewers (Codex present) | Codex absent | Skill-specific efficiency rule |
|-------|------|---------------------------|--------------|-------------------------------|
| `verify-claim` | **0 — mechanical** | none — `grep`/`sed`/`git` only, no LLM jury, by design | same | It IS the cheap pre-filter. Never escalate inside it; it returns CONFIRMED/FALSIFIED/UNVERIFIABLE and the caller decides. |
| `devils-pair` | **2 — pair** | A = Claude subagent (murder-board stance); B = `codex exec` (hostile-competitor stance) | A + B = two Claude subagents, distinct stances | Run the static pre-gate first: Tier-0 change → say so and exit without a review. On reviewer **disagreement**, do not resolve it — recommend `attack-fix`. |
| `attack-fix` | **3 — jury + verifier** | A = Claude subagent; B = `codex exec`; C = Claude subagent (skeptic stance); meta-judge/+1 verifier = `codex exec` over the jury's findings | A/B/C = three Claude subagents, three stances; verifier = orchestrator | Pre-gate: trivial diff → warn it's Tier-0/1 and offer to downgrade to `devils-pair`. **Early exit:** A+B decisively unanimous → skip C and the verifier. |
| `attack-finding` | bounded (one claim) | A = Claude subagent (reachability + source verification); B = `codex exec` (independent REAL/FALSE/BY-DESIGN/LATENT verdict) | A + B = two Claude subagents | One claim only — never a 3-jury. Agree → done; disagree → orchestrator meta-judges once. |
| `full-codebase` | **3 per domain** | per domain: 1 Claude subagent + 1 `codex exec` over the domain file list; one cross-family verifier pass over the merged HIGH findings | per domain: 2 Claude subagents, distinct stances | Domain pre-gate: with `--since`, domains with no changed files are skipped entirely. The +1 verifier runs **once** at aggregation, not per domain. |
| `pre-mortem` | 3 stances (design, not diff) | stance "senior engineer" = Claude subagent; "on-call" = `codex exec`; "skeptic" = Claude subagent | all 3 = Claude subagents | Reviews a decision, not a diff — no static diff gate. Already bounded to one decision; never spawn more than the 3 stances. |

---

## 7. Research basis

- **Static pre-gate beats LLM-confidence cascades** — arXiv:2605.06350.
- **Escalation signals (LOC / file type / blast radius), AUC 0.96 / 131K reviews** — arXiv:2601.00753.
- **Disagreement-gated escalation, 95.2% @ 3.5% escalation** — DREAM, arXiv:2602.06526.
- **Quorum early-exit, 19-55% cost cut @ <0.2% quality loss** — arXiv:2601.05777.
- **Jury size k=3 sweet spot** — arXiv:2604.13717.
- **3 generators + 1 cross-family verifier: +10.3pp precision, −31.5pp FP** — arXiv:2604.21282.
- **Cross-family panels beat single reviewer +11-22pp at 7× lower cost** — PoLL, arXiv:2404.18796.
- **Independent + merge ≥ debate at ~half the tokens** — MARS arXiv:2509.20502; "Stop Overvaluing MAD" arXiv:2502.08788.
- **Context isolation +4 F1 / +11pp critical; in-session repetition does not help** — arXiv:2603.12123.
- **Same-family correlated-error penalty +6.6-7.6pp** — arXiv:2506.07962.
- **Multi-turn review raises FP ~62%; same-model debate inflates confidence** — arXiv:2603.16244, arXiv:2505.19184.
- **Solo LLM code-review F1 ≈ 19% — jury structure is necessary for recall** — arXiv:2509.01494.

---

## 8. Version notification

steelman-suite ships fast and this contract evolves. Every skill, as its first
action, runs `bin/check-version.sh` and surfaces a one-line notice when the
installed copy is behind the published version.

The check obeys the same efficiency rule as everything else here — **it must
never cost the user time:**

- **Throttled** — one network call per 24h maximum; every other invocation is a
  local cache read (<1ms).
- **Never blocks** — a stale cache is refreshed in a detached background process
  (stale-while-revalidate); the calling skill never waits on the network. A
  notice is at most 24h stale, which is fine for "a new version exists".
- **Never errors loudly** — offline, no `curl`/`wget`, or a parse failure →
  silent, no notice, exit 0.
- **Deterministic source** — the remote location is a hardcoded constant in
  `bin/check-version.sh`. Idea borrowed from GSD's `check-latest-version.cjs`:
  the update source is not a runtime choice the executing model can get wrong.

**Skill contract:** run `bin/check-version.sh`; if stdout begins
`STEELMAN_UPDATE available:`, append that single line to your result. If it
begins `STEELMAN_UPDATE none`, say nothing. This check must never delay or block
the review itself.
