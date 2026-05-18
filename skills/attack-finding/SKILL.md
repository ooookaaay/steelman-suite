---
name: steelman:attack-finding
description: Use this skill when the user has an existing claimed bug, audit finding, security issue report, or CVE-style claim and wants formal meta-review BEFORE acting on it. The skill verifies the claim against actual source code, runs heterogeneous multi-AI jury, and returns a calibrated REAL / FALSE-POSITIVE / BY-DESIGN / LATENT-NOT-FIRE verdict with execution evidence. Use specifically when (a) the user pastes a bug claim from another AI / static analyzer / audit report and asks "is this real?" / «правда ли это» / «codex говорит что», (b) a CodeRabbit / Sonar / Snyk finding lands in PR and needs triage before fixing, (c) the user is about to write a fix based on an AI claim and you want to confirm the underlying bug exists. Do NOT use to attack a CHANGE the user just made — that's `steelman:attack-fix`. This skill attacks a CLAIM about existing code.
---

# steelman:attack-finding

> **Mandate** (per OpenAI CriticGPT 2024 — 60% of LLM-claimed bugs are wrong about something material):
> Your job is to **falsify the claim**, not to confirm it. The default verdict is FALSE until proven REAL by execution evidence.

## Why this skill exists

LLM bug claims have a known precision problem. Codex meta-review of itself (2026-05-18 ugolovkin audit cycle) found **6 of 21 HIGH findings were dormant** (flag off / migration applied / unreachable) — codex systematically over-rates severity when it can't verify production reachability. Static analyzers do this too. Single-shot LLM reviews can hallucinate function signatures and miss `if guard:` clauses.

Triage is cheap. Skip it and you waste a deploy cycle fixing a phantom.

## Inputs

```bash
/steelman:attack-finding <claim>
```

Where `<claim>` is one of:
- A short prose claim: `/steelman:attack-finding "src/foo.py:42 — race condition between read and write"`
- A path to a finding file: `/steelman:attack-finding .planning/audits/AUDIT-cascade.md HIGH-3`
- A diff URL + line number from a PR comment
- A markdown block pasted via stdin

The claim MUST cite:
- A specific file (path)
- A specific line range
- A concrete failure mode (what happens, when)

If the claim is missing any of these, ask the user to add them before proceeding. Don't waste a jury round on a vague claim.

## Procedure

### Step 1 — Parse and ground the claim

Extract from the input:

| Field | Required | Example |
|---|---|---|
| `file_path` | ✓ | `src/processing/article_processor.py` |
| `line_range` | ✓ | `956-961` |
| `failure_mode` | ✓ | `track_when_criminal aliases pass via has_business_keyword alone` |
| `trigger_condition` | recommended | `when body contains business keyword but article has no criminal signal` |
| `claimed_severity` | optional | `HIGH` |
| `claimed_by` | optional | `Codex audit 260518 eval-ingestion HIGH-1` |

If any required field is missing, return:

```
Cannot evaluate. The claim is missing: {field}. Please re-invoke with a complete claim citing file + line + failure mode.
```

### Step 2 — Verify the file:line citation against actual source

```bash
# Confirm the file exists at the claimed path
test -f "$FILE_PATH" || RESULT="UNVERIFIABLE: file not found"

# Read the cited lines + 10 surrounding context
sed -n "$((LINE_START - 10)),$((LINE_END + 10))p" "$FILE_PATH"
```

If the cited lines don't match the claim's description of the code (e.g. claim says "function `foo`" but lines show `function bar`), return:

```
UNVERIFIABLE — line:file citation does not match the described code.
Claim referenced: {claim description}
Actual lines: {actual code}
The claim may be stale (file refactored since claim was made) or hallucinated. Re-confirm with the source.
```

### Step 3 — Check against operator binding contracts

**This is the load-bearing step that closes the 6-of-21-dormant gap.** Per the 2026-05-18 audit cycle: codex meta-review confirmed that several "HIGH bugs" were actually **operator-binding by-design behavior** flagged as bugs.

Check in order:
1. `CLAUDE.md` (if present) for explicit binding clauses about this file / pattern
2. `~/.claude/projects/<project>/memory/` for operator preferences
3. `.planning/notes/` for ADRs / binding decisions
4. Git log of the cited file (`git log --follow <file>`) for "by design" / "operator binding" commits

If a binding contract explicitly endorses the flagged behavior, return:

```
BY-DESIGN — codex/auditor flagged behavior that is an explicit operator binding.

Binding location: {file:line}
Binding quote: "{relevant text}"
Verdict: this is NOT a bug. The claim should be retired from the backlog with rationale: "binding contract explicitly mandates {behavior}".
```

### Step 4 — Check production reachability

For each claim, run:

```bash
# Is the cited code path actually reachable from production?
# Three tests:

# 1. Caller existence
grep -rn "$(extract_symbol_name_from_lines)" src/ | grep -v test_

# 2. Feature flag state
grep -rn "$(extract_flag_name_if_any)" src/storage/runtime_config*.py src/config.py

# 3. Recent execution (logs)
docker logs ${CONTAINER:-app} --since 24h 2>&1 | grep "$(execution_signature)" | head -5
```

If callers don't exist OR feature flag is `false` by default OR no execution signature in logs:

```
LATENT-NOT-FIRE — claim is technically correct but code path doesn't execute in current production state.

Reachability gate: {what blocks reachability}
Recommendation: keep in backlog with `latent` tag. Re-evaluate when the gate opens (flag flipped / caller added / deployment target changes).
```

### Step 5 — Spawn falsification jury (≥2 reviewers, falsification-mode)

Per [Heuer's ACH](https://www.cia.gov/library/center-for-the-study-of-intelligence/csi-publications/books-and-monographs/psychology-of-intelligence-analysis/index.html): **score evidence by disproof, not proof.** The reviewers' job is to find one specific way the claim is wrong.

Spawn 2-3 independent reviewers (no cross-talk, MARS pattern):

| Reviewer | Family | Falsification stance |
|---|---|---|
| Reviewer A | Same family as the claimant (if known) | "What did the original analysis miss that would make this NOT a bug?" |
| Reviewer B | Cross-family | "Is there a `if guard:` upstream that prevents this failure mode from triggering?" |
| Reviewer C | Optional, if available | "Has this been fixed in a commit the claimant didn't see? Check `git log -p $file`" |

Each reviewer is required to:
- Read the cited code IN FULL (not just the line range)
- Trace at least one upstream caller
- Trace at least one downstream consumer
- Attempt to write a reproducible failing test
- Return verdict + execution evidence

### Step 6 — Aggregate (MARS, falsification-weighted)

Aggregate with a **falsification bias** — REAL requires positive evidence, FALSE is the null hypothesis:

| Reviewer votes | Aggregate verdict |
|---|---|
| ≥2 reviewers produce a reproducible failing test | **CONFIRMED REAL** |
| ≥2 reviewers identify a `BY-DESIGN` binding | **BY-DESIGN** |
| ≥2 reviewers find a guarding `if` clause | **FALSE-POSITIVE** |
| All reviewers say reachability blocked | **LATENT-NOT-FIRE** |
| Mixed (1 REAL + 1 FALSE) with no test | **NEEDS-OPERATOR-INPUT** |
| All reviewers say "looks fine" | **LIKELY-FALSE-POSITIVE** (default-to-null) |

### Step 7 — Output

```markdown
# Steelman attack on finding: {short title}

## Verdict
**{CONFIRMED REAL | LATENT-NOT-FIRE | BY-DESIGN | FALSE-POSITIVE | NEEDS-OPERATOR-INPUT | LIKELY-FALSE-POSITIVE}**

Calibrated confidence: {0-1} — {N} reviewers, falsification-weighted

## Source claim
{quoted}

## What we verified
- File:line citation: ✓ (or ✗ with detail)
- Operator binding contract check: {result}
- Production reachability: {result}

## Reviewer falsification attempts

### Reviewer A ({family})
**Falsification attempt:** {what they tried}
**Result:** {evidence found / not found}
**Verdict:** {REAL / FALSE / BY-DESIGN / LATENT}

### Reviewer B ({family})
{same shape}

## Reproducible test
{If REAL: failing test the operator can paste; if FALSE: the guarding code that makes it pass}

## Recommendation
**If CONFIRMED REAL:** Fix with concrete patch outline.
**If LATENT-NOT-FIRE:** Keep in backlog tagged `latent-{gate}`. Re-evaluate when {trigger}.
**If BY-DESIGN:** Retire from backlog. Document binding location in `.planning/notes/findings-by-design.md`.
**If FALSE-POSITIVE:** Document the false-positive pattern in `evals/false-positive-patterns.md` so the suite learns.
**If NEEDS-OPERATOR-INPUT:** Specific question for the operator (1 sentence).
```

## Failure modes you MUST handle

1. **No source code available** — Refuse with clear message; this skill needs the codebase.

2. **Claim cites a deleted file** — Run `git log --follow --diff-filter=D -- <path>` to find when it was deleted. Output: `UNVERIFIABLE — file deleted in commit {hash}`.

3. **Multiple reviewers OFFLINE** — Drop to 1 reviewer + dialectical-bootstrap (2 passes, fresh contexts, opposite temperatures). Tag confidence as reduced.

4. **The claim is about a binding policy itself** ("this binding is wrong") — Out of scope. Refuse and suggest the user open a discussion with the operator instead.

5. **The claim references a recently-fixed bug** — Check `git log -p --since='14 days ago' -- <file>` for a fix. If found: `ALREADY-FIXED in commit {hash}`. Retire from backlog.

## Anti-patterns to reject

- ❌ Single reviewer accepting the claim at face value
- ❌ Reviewer's verdict without execution evidence
- ❌ Not checking CLAUDE.md / operator bindings before flagging
- ❌ Not checking production reachability
- ❌ Confirming bias ("the claim looks plausible → REAL")

## Auto-trigger conditions

This skill auto-triggers when:

- The user pastes a markdown block matching `### (HIGH|MEDIUM|LOW)-\d+:` (codex / Sonar / Snyk finding format)
- The user's message contains «правда ли», «is this real», «codex говорит», «найдено в audit», «from CodeRabbit», «from Snyk»
- A new file matching `AUDIT-*.md` / `FINDINGS-*.md` lands in the project's `.planning/` tree
- The user invokes `/steelman:attack-finding` directly

## Related skills

- `steelman:attack-fix` — attack a code CHANGE (not a claim about existing code)
- `steelman:verify-claim` — lightweight grep-only verification (no jury)

## References

- [Heuer's Analysis of Competing Hypotheses](https://www.cia.gov/library/center-for-the-study-of-intelligence/csi-publications/books-and-monographs/psychology-of-intelligence-analysis/index.html)
- [CriticGPT, McAleese et al. 2024](https://arxiv.org/abs/2407.00215)
- [Refute-or-Promote, 2024](https://arxiv.org/abs/2406.00374) — correlated-prior failure mode of single-family review
- Field-tested example: [ooookaaay/ugolovkin DEVILS-ADVOCATE-2](https://github.com/ooookaaay/ugolovkin/blob/v2-dev/.planning/audit-260518/DEVILS-ADVOCATE-2-attack-codex-unfixed.md) — triaged 32 codex HIGH findings → 9 confirmed-real, 13 latent, 4 false-positive, 2 by-design, 4 operationally-irrelevant.
