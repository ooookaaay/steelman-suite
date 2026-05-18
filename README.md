# steelman-suite

> **Adversarial review skills that build the strongest case AGAINST your code.**
> SOTA-2026 multi-AI devil's advocate for Claude Code / Codex CLI / Cursor / Gemini CLI / any [Agent Skills](https://agentskills.io)-compatible host.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Skill Standard](https://img.shields.io/badge/Agent%20Skills-compliant-blue)](https://agentskills.io)

## Why

LLM coding assistants are **systemically sycophantic**. Three independently-steerable sycophantic behaviors live in latent space (see [_Sycophancy Is Not One Thing_, 2025](https://arxiv.org/abs/2502.13095)) — the model defaults to agreeing with whatever framing you give it. When you ask «is my fix good?», it says yes.

Catholic Church figured this out in 1587 (the original `advocatus diaboli`). Prussian general staff figured it out in 1812 (`Kriegsspiel`). CIA Team B did it in 1976. OpenAI's [CriticGPT](https://arxiv.org/abs/2407.00215) (2024) does it internally — 85% bug-catch vs 25% for unaided humans — but nobody shipped a productized version. Anthropic's own 2026 internal study (Orr) showed reviewers downgrade severity by 30%+ when given implementer framing.

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

## What

| Skill | Single-purpose summary |
|---|---|
| `steelman:devils-pair` | **Workhorse.** 2 reviewers (same + cross-family) in parallel, ≤60s, smell-test |
| `steelman:attack-fix` | Multi-AI jury on a specific commit/diff — for high-blast-radius changes |
| `steelman:attack-finding` | Meta-review of a claimed bug from another AI / static analyzer / audit |
| `steelman:verify-claim` | Mechanical (grep/sed) verification of a single file:line claim |
| `steelman:full-codebase` | Pre-release whole-repo pass, domain-parallel |
| `steelman:pre-mortem` | Klein past-tense failure brainstorm before architectural commitments |

Each skill follows the **SOTA-2026 design contract** (see [docs/PATTERNS.md](docs/PATTERNS.md)):

1. **Heterogeneous multi-model jury** (≥3 providers, ≥2/3 agreement)
2. **Strip implementer's reasoning trace** before review (counter-sycophancy)
3. **Extended thinking ≥2k tokens + minimax-ToT** (two-player zero-sum framing)
4. **Tool-interactive critic** — must actually run code to verify; claim without execution = `[UNVERIFIED]`
5. **Calibrated confidence** (Brier/ECE) — not raw probabilities; recalibrate monthly against logged outcomes

Plus the [MARS pattern](docs/PATTERNS.md#mars) — independent reviewers + meta-reviewer, **no cross-talk** — to avoid groupthink (per arxiv 2503.12029).

## How to install

### Claude Code (canonical)

```bash
cd ~/.claude
git clone https://github.com/ooookaaay/steelman-suite skills/steelman
```

Or install as an [Agent Skills plugin](https://agentskills.io):

```bash
/install steelman-suite
```

### Codex CLI

```bash
mkdir -p ~/.codex/plugins
git clone https://github.com/ooookaaay/steelman-suite ~/.codex/plugins/steelman-suite
```

### Cursor / Gemini CLI / Junie / Kiro / Goose / Copilot Workspace

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

- `pre-commit-attack.sh` — runs `attack-fix` automatically on `git commit` PreToolUse
- `post-fix-pair.sh` — runs `devils-pair` automatically after Edit/Write operations modify >5 lines

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

## SOTA-2026 features

- **Heterogeneous multi-model jury** routing across Claude Opus 4.7 / Codex GPT-5.5 / DeepSeek R1 / Gemini 2.5 — `≥2/3` agreement threshold prevents single-family correlated errors
- **Anti-sycophancy framing** strips implementer's reasoning trace before passing to reviewers (per Anthropic Orr 2026 — `9/10` Critical findings when redacted vs `6-7/10` when framed)
- **Tool-interactive verification** — every claimed finding is executed against actual source. No `[UNVERIFIED]` allowed in final output
- **Calibrated confidence** via Brier-score recalibration on a sliding window of logged outcomes
- **Steelman schema** — every finding ships with: (a) steelman of the original code, (b) attack vector, (c) verifiable `file:line`, (d) reproducible failing test
- **Independence-gate subagent** for self-critique (the [MARS pattern](docs/PATTERNS.md#mars), not free-for-all debate)

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

## License

[MIT](LICENSE) — use freely, attribute kindly.
