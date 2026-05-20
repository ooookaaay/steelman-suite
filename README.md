# steelman-suite

> **Adversarial review skills that build the strongest case AGAINST your code.**
> Multi-AI devil's advocate for Claude Code / Codex CLI / Cursor / Gemini CLI / any [Agent Skills](https://agentskills.io)-compatible host.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Skill Standard](https://img.shields.io/badge/Agent%20Skills-compliant-blue)](https://agentskills.io)

## Why "steelman"

The opposite of a **straw man**: instead of attacking a weak caricature of a position, you build the **strongest possible version** of it and attack that. The term comes from rationalist / philosophical practice — steelman your opponent's argument before rebutting, otherwise you're just shadowboxing.

This suite flips the framing onto your own code. The reviewer's job is to build the strongest possible case **against** the change or claim. Charity-of-interpretation toward the code is the enemy. If the fix looks correct, the reviewer has not looked hard enough.

The other half of the contract is anti-sycophancy: each reviewer is spawned without the implementer's reasoning trace, so it can't be primed by the framing «here's what I was trying to do». OpenAI's [CriticGPT](https://arxiv.org/abs/2407.00215) (2024) is the closest commercial-grade analog — 85% bug-catch vs 25% unaided. This suite is the productized version of the same idea for any [Agent Skills](https://agentskills.io)-compatible host.

## Why

LLM coding assistants are **systemically sycophantic**. Three independently-steerable sycophantic behaviors live in latent space (see [_Sycophancy Is Not One Thing_, 2025](https://arxiv.org/abs/2502.13095)) — the model defaults to agreeing with whatever framing you give it. When you ask «is my fix good?», it says yes.

The institutional fix is well known. The Catholic Church canonization process invented the `advocatus diaboli` in 1587. The Prussian general staff codified it as `Kriegsspiel` in 1812. The CIA used the same pattern in their Team B exercise in 1976. The discipline is older than computing: assign one team to attack what the other team built — and reward them for it.

CriticGPT (2024) showed the same effect works on LLM-written code. Internal Anthropic work in 2026 showed that reviewers downgrade severity by 30%+ when they see the implementer's reasoning trace — exactly the framing every IDE auto-feeds to its review pass.

**This suite ships the productized version.**

## Design principle

> **Stay out of the way unless you have something to say.**

Adversarial review is only valuable when its findings are real AND its latency is acceptable. A million double-checks that slow every commit by 10 minutes destroys flow. The suite picks the right tool per change-blast-radius:

| Change shape | Recommended skill | Wall-clock | Cost | When |
|---|---|---|---|---|
| Routine commits, ≤50 LOC, low blast-radius | nothing — skip | 0s | $0 | normal flow |
| Same as above, want a smell-test | `steelman:devils-pair` | ~60s | ~$0.05 | opt-in, before `git push` |
| Logic change, hot path, prod-data risk | `steelman:attack-fix` | 5-10min | ~$0.50-2 | explicit invocation |
| Architectural decision pre-commit | `steelman:pre-mortem` | 5min | ~$0.30 | before locking in design |
| Triaging an AI-claimed bug | `steelman:attack-finding` | 2-5min | ~$0.10-0.50 | when AI claims something |
| Single file:line claim, fast filter | `steelman:verify-claim` | ≤10s | $0 (mechanical) | filter long claim lists |
| Pre-release whole-repo audit | `steelman:full-codebase` | 30-60min | $5-20 | manual, release-gate only |

**Hooks are OPT-IN by default.** The suite does not auto-fire on `git commit`. You enable hooks for the chains you trust. See [docs/HOOKS.md](docs/HOOKS.md).

### How the suite decides what to run

v0.2.0 makes "stay out of the way" mechanical. Before any model is called, a **static pre-gate** reads the change metadata — lines changed, files touched, whether a high-blast path (migrations / auth / publish) is hit — and picks a tier:

| Tier | Change | What runs |
|---|---|---|
| 0 | tiny, no blast-radius | nothing |
| 1 | moderate | one context-isolated reviewer |
| 2 | larger / multi-file | Claude + Codex pair |
| 3 | high-blast path / very large | 3-reviewer jury + cross-family verifier |

It does **not** pre-pay for the top tier. It runs the cheap tier, then escalates **only when the reviewers disagree** — inter-reviewer disagreement is the escalation signal, and in practice it fires on ~3-4% of changes. When reviewers already agree, the run stops early at quorum. The full routing + efficiency contract is [docs/ENGINES.md](docs/ENGINES.md), grounded in 2026 research (see its §7).

## What

| Skill | Single-purpose summary |
|---|---|
| `steelman:devils-pair` | **Workhorse.** 2 reviewers (same + cross-family) in parallel, ≤60s, smell-test |
| `steelman:attack-fix` | Multi-AI jury on a specific commit/diff — for high-blast-radius changes |
| `steelman:attack-finding` | Meta-review of a claimed bug from another AI / static analyzer / audit |
| `steelman:verify-claim` | Mechanical (grep/sed) verification of a single file:line claim |
| `steelman:full-codebase` | Pre-release whole-repo pass, domain-parallel |
| `steelman:pre-mortem` | Klein past-tense failure brainstorm before architectural commitments |

Each skill follows the same design contract — hooks and auto-trigger wiring: [docs/HOOKS.md](docs/HOOKS.md); engine routing, tier selection, and efficiency rules: [docs/ENGINES.md](docs/ENGINES.md):

1. **Heterogeneous multi-model jury** — reviewers come from different model families (Claude / Codex / DeepSeek / Gemini), with ≥2-of-3 agreement required. Same-family LLMs share blind spots; cross-family forces disagreement that's actually informative.
2. **Strip the implementer's reasoning trace** before review. The reviewer sees the code, not the framing — kills the «I'm sure this is right because the implementer was sure» failure mode.
3. **Extended thinking + two-player zero-sum framing** — the reviewer is rewarded for blocking a real bug, penalized for blocking a phantom. Asymmetric incentive prevents drift toward «looks fine to me».
4. **Tool-interactive verification** — every claim must be backed by running code (`grep`, `Read`, `pytest`). Claim without execution = `[UNVERIFIED]` and gets downgraded.
5. **Categorical verdicts, majority-aggregated** — each reviewer returns one of REAL / LIKELY-REAL / UNCLEAR / LIKELY-FALSE / FALSE; the meta-reviewer takes a cross-family majority. No fabricated probability numbers. Brier-weighted *calibrated* confidence is on the v0.3 roadmap — deliberately deferred until enough logged run data exists to calibrate against.

Plus the **MARS pattern** — short for **Multi-Agent Reviewers in Separation**: each reviewer writes its findings alone, in isolation, then an aggregator merges them. No debate between reviewers, no cross-talk, no chance to anchor on each other. Free-for-all multi-agent debate (everyone reads everyone) actually performs *worse* than independent reviewers — see [_Stop Overvaluing MAD_, 2025](https://arxiv.org/abs/2502.08788) for the empirical result. Independent + aggregator is the same lesson production audit firms learned a century ago.

## How to install

### Claude Code (canonical)

```bash
cd ~/.claude
git clone https://github.com/ooookaaay/steelman-suite skills/steelman
```

**Works out of the box with only the `claude` CLI installed.** `codex` and other AI providers are optional and auto-detected at runtime. When only one provider is available, the suite runs a dialectical bootstrap — two independent passes with different adversarial stances — instead of a cross-family jury. No config changes needed.

If/when published to an Agent Skills registry, `/install steelman-suite` will be the one-liner install — until then, use the `git clone` above.

### Codex CLI

```bash
mkdir -p ~/.codex/plugins
git clone https://github.com/ooookaaay/steelman-suite ~/.codex/plugins/steelman-suite
```

### Cursor

```bash
mkdir -p ~/.cursor/skills
git clone https://github.com/ooookaaay/steelman-suite ~/.cursor/skills/steelman-suite
```

### Gemini CLI

```bash
mkdir -p ~/.gemini/plugins
git clone https://github.com/ooookaaay/steelman-suite ~/.gemini/plugins/steelman-suite
```

### Aider

```bash
mkdir -p ~/.aider/skills
git clone https://github.com/ooookaaay/steelman-suite ~/.aider/skills/steelman-suite
```

### Junie / Kiro / Goose / Copilot Workspace / other Agent Skills-compatible hosts

All [agentskills.io](https://agentskills.io)-compatible hosts: drop the repo into their skills directory. The SKILL.md format is the cross-vendor standard (Dec 18 2025+).

## How to use

```bash
# Attack a commit
/steelman:attack-fix HEAD

# Attack a finding (paste the bug claim or pass a markdown file)
/steelman:attack-finding ".planning/audit/AUDIT.md HIGH-3"

# Quick cross-AI sanity check before commit
/steelman:devils-pair --on-current-diff

# Pre-release full pass — domain-parallel
/steelman:full-codebase

# Past-tense failure brainstorm
/steelman:pre-mortem "we're about to migrate from SQLite to Postgres"

# Verify a claim
/steelman:verify-claim "src/processing/article_processor.py:956 — has_business_keyword bypasses tier gate"
```

## Auto-trigger via hooks

The `hooks/` directory contains [Claude Code hooks](https://docs.claude.com/en/docs/claude-code/hooks) you can wire into `~/.claude/settings.json`:

- `pre-push-attack-on-high-blast.sh` — runs `attack-fix` on `git push` (PreToolUse), but only when the diff touches a high-blast path
- `post-edit-devils-pair.sh` — runs `devils-pair` in the background after Edit/Write operations cross a LOC threshold

See [docs/HOOKS.md](docs/HOOKS.md) for setup recipes.

## How is this different from existing tools

| Tool | Free | Local-only | Composable suite | Bidirectional cross-AI | Atomic on commit | DA-specific stance | Hook-driven |
|---|---|---|---|---|---|---|---|
| CodeRabbit AI | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Cursor review | ✓ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Copilot for PRs | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Sourcery | partial | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| brandonsimpson/devils-advocate | ✓ | ✓ | ❌ | ❌ | ✓ | ✓ | ✓ |
| wan-huiyan/agent-review-panel | ❌ | ❌ | ❌ | ✓ | ❌ | ❌ | ❌ |
| robertoecf/adversarial-review | ✓ | ✓ | ❌ | ✓ | ✓ | partial | ❌ |
| **steelman-suite** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

We're the only one that hits all 7 axes simultaneously.

## Design features

- **Heterogeneous multi-model jury** routes across Claude Opus 4.7 / Codex GPT-5.5 / DeepSeek R1 / Gemini 2.5. `≥2/3` agreement threshold prevents single-family correlated errors — when two different model families both agree a bug is real, it usually is.
- **Anti-sycophancy framing** strips the implementer's reasoning trace before passing the diff to reviewers. Anthropic's internal 2026 work measured 9/10 Critical-severity findings when the trace was redacted, vs 6-7/10 when reviewers saw «here's what I was trying to do».
- **Tool-interactive verification** — every claimed finding is executed against actual source code (`grep` / `Read` / `pytest`). `[UNVERIFIED]` claims get downgraded and never end up in the final output.
- **Categorical verdicts over fabricated probabilities** — reviewers emit one of REAL / LIKELY-REAL / UNCLEAR / LIKELY-FALSE / FALSE, aggregated by cross-family majority. Raw model «98% certain» is noise, so the suite does not surface a confidence number at all. Brier-weighted calibrated confidence is a v0.3 roadmap item, deferred until logged outcomes exist to calibrate against.
- **Steelman finding schema** — every output ships four things: (a) the strongest case FOR the original code, (b) the attack vector, (c) a verifiable `file:line`, (d) a reproducible failing test. Three of the four can be checked without re-running the LLM.
- **MARS pattern** (**M**ulti-**A**gent **R**eviewers in **S**eparation) — independent reviewers + aggregator, no debate between them. Free-for-all multi-agent debate underperforms independent + merge (see [_Stop Overvaluing MAD_, 2025](https://arxiv.org/abs/2502.08788)).
- **Efficiency-gated invocation** — a zero-LLM static pre-gate picks the review tier from diff metadata; the expensive cross-model jury fires only when a cheap pass leaves the verdict open (inter-reviewer disagreement), and stops early on quorum. The expensive tier is spent at the right moment, not by default. See [docs/ENGINES.md](docs/ENGINES.md).

## Limitations

This suite is **opinionated** about adversarial review. It won't:

- Generate code (use Claude / Codex / Cursor for that)
- Rewrite your code (use Sourcery / Sonar for that)
- Find style violations (use `ruff` / `prettier` for that)
- Replace human review on safety-critical paths (it's a force multiplier, not a substitute)

## Acknowledgements

Built on the shoulders of:

- [Catholic Church canonization process](https://en.wikipedia.org/wiki/Advocatus_Diaboli) (1587–1983)
- [Prussian Kriegsspiel](https://en.wikipedia.org/wiki/Kriegsspiel) (1812)
- [CIA Team B](https://en.wikipedia.org/wiki/Team_B) (1976)
- [Janis groupthink remedy](https://en.wikipedia.org/wiki/Groupthink) (Janis 1972)
- [Fagan inspections](https://en.wikipedia.org/wiki/Fagan_inspection) (Fagan 1976)
- [Klein pre-mortem](https://hbr.org/2007/09/performing-a-project-premortem) (HBR 2007)
- [CriticGPT](https://arxiv.org/abs/2407.00215) (McAleese et al. 2024)
- [Panel-of-LLM-Judges](https://arxiv.org/abs/2404.18796) (Verga et al. 2024)
- [Jury-on-Demand](https://arxiv.org/abs/2512.01786) (2025)
- [Stop Overvaluing MAD](https://arxiv.org/abs/2502.08788) (2025)
- [Sycophancy Is Not One Thing](https://arxiv.org/abs/2502.13095) (2025)
- Anthropic's [Agent Skills](https://docs.claude.com/en/docs/claude-code/skills) spec (2025-12-18)

Field-tested in production at [ooookaaay/ugolovkin](https://github.com/ooookaaay/ugolovkin) — 2026-05-18 audit cycle caught **two real regressions in shipped fixes** (a non-picklable APScheduler closure and a sycophantic alert-flag flip) before they hit operator-driven traffic.

### Field evidence — 2026-05-18 audit cycle

Commit range: [`429d93a4..04fd7afc`](https://github.com/ooookaaay/ugolovkin/compare/429d93a4..04fd7afc) on `ooookaaay/ugolovkin` (private mirror — public version at [ooookaaay/ugolovkin](https://github.com/ooookaaay/ugolovkin)).

The suite triaged 32 codex HIGH findings → **9 confirmed-real, 13 latent-not-fire, 4 false-positive, 2 by-design (operator binding), 4 operationally-irrelevant.** Of the 9 confirmed-real, 2 were regressions introduced by **other** AI-generated fixes earlier in the same session:

1. **Non-picklable APScheduler closure** — `scheduler_jobs.py` registered a job whose target was a closure capturing a per-request lambda. APScheduler's `SQLAlchemyJobStore` pickles job targets at registration time; restart would have crashed silently. `steelman:attack-fix` reviewer B reproduced via `pickle.dumps(job.func)` in the execution_evidence field.
2. **Sycophantic alert-flag flip** — a fix flipped a runtime alert threshold from `5%` to `25%` to silence a noisy alert without addressing the underlying fallback rate. Reviewer A flagged this as «the fix doesn't address the bug, it hides the symptom» — the `attack` field cited the original bug report directly contradicting the new threshold.

The other 13 LATENT-NOT-FIRE findings were exactly the dormant code paths that codex over-rated as HIGH — feature flag off, migration not yet applied, no callers — caught by Step 4 (production reachability check) in `attack-finding`.

### Field evidence — 2026-05-19 v2.15 milestone close

`steelman:full-codebase` ran as the release gate before `/gsd-complete-milestone v2.15` (run `v2.15-fullpass-20260519T1730`): 5 domains, ~55k LOC (88% of `src/`), 38 min, 5 parallel agents — one domain crashed on an API 529 and was re-spawned smaller. Result: **8 confirmed-real HIGH**, 8 latent-not-fire, 13 by-design, 9 false-positive (self-corrected in-audit).

The headline finding — **D-F1** — is the clearest case yet for *why `pre-mortem` and `full-codebase` are not interchangeable*. Earlier the same day, a `steelman:pre-mortem` on a hotfix design had done its job well: it forced a PIVOT to a narrower, safer merge rule. But the full-codebase pass then caught that the *shipped* hotfix (already deployed to production) could not fire on its own target — «ч.4 ст.160 УК РФ» and «ч. 4 ст. 160 УК РФ» normalised to different strings, so the merge it was written to perform was silently rejected. An existing unit test had even pinned the buggy contract. The pre-mortem missed it because its attention was on the rule's *architecture*; the bug was a whitespace-equality detail one layer down. Hot-fixed in-session with a reproducer test — hours before a hard publish deadline.

**Lesson, now folded into the skills:** a design `pre-mortem` and a `full-codebase` pass are complementary, not redundant. Pre-mortem catches architectural and operational failure modes; full-codebase catches the small predicate / edge-case bugs — string equality, whitespace, off-by-one, regex gaps — that the pre-mortem's framing draws attention away from. Run both before a milestone tag: pre-mortem on the design, full-codebase on the code.

### Field evidence — 2026-05-20 cascade-classifier change

`steelman:attack-fix` ran three rounds on a ~90-LOC change to a production LLM-classifier cascade (a call-volume-reduction phase). The change had **already passed `ruff`, `mypy --strict`, its full unit-test suite, and the F1 regression corpus — all green** — and was queued for deploy.

Round 1 caught **3 real defects**: a config change that was a silent no-op (the widened value was never read on the hot path, so the "fix" did nothing), plus two recall-regression code paths that skipped the LLM for clusters it should have classified. Round 2 caught a **4th, architectural**: one of the three sub-changes had no safe target population at all once another sub-change shipped — it was reverted wholesale rather than patched. Round 3, on the corrected code, was clean.

**Why the green test suite missed all four:** the unit tests were written by the same process that wrote the code, from the same flawed mental model — they asserted the buggy behaviour and passed. Adversarial reviewers, spawned without the implementer's reasoning trace, don't share that model. This is the case the suite exists for — the highest-value catches are the bugs that pass CI. It is also the case for **gating on deploy, not on every commit**: three rounds cost ~40 minutes and real money, which is the right trade before a cascade hits production and the wrong one on a routine push.

## License

[MIT](LICENSE) — use freely, attribute kindly.
