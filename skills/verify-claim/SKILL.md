---
name: steelman:verify-claim
description: Use this skill for LIGHTWEIGHT verification of a single file:line bug claim — no multi-AI jury, no spawn, no token cost beyond a few greps and reads. Returns CONFIRMED / FALSIFIED / UNVERIFIABLE in ≤10 seconds wall-clock. Use specifically when (a) the user wants to check ONE claim against the source code without spinning up the full attack-finding jury, (b) inside another skill's chain (verify before deeper review), (c) the user pastes a single specific bug claim and asks «правда ли», (d) you're triaging through a long list of findings and want fast filtering. The skill is mechanical (grep/sed/git) — no LLM reasoning beyond pattern matching. For deeper analysis with calibrated confidence + cross-AI jury, use `steelman:attack-finding` instead.
---

# steelman:verify-claim

> **Mandate:** Falsify the claim in ≤10 seconds. Mechanical evidence, no jury.

## Why this skill exists

Most LLM-claimed bugs cite a specific `file:line`. The cheapest possible verification is to just **read the cited line + immediate surroundings + grep for the symbol**. If the claim describes code that doesn't exist there, or if a guarding `if` clause is already present, the claim is dead — no jury needed.

Field example: in the 2026-05-18 audit cycle, ~10 of 47 HIGH findings were verifiable as `UNCLEAR` or `LATENT` purely from `grep` + `sed` evidence. Running the full jury on those would have been wasted credits.

## Inputs

```bash
/steelman:verify-claim "<file>:<line> — <claim description>"
```

Examples:
- `/steelman:verify-claim "src/processing/article_processor.py:956 — has_business_keyword bypasses tier gate"`
- `/steelman:verify-claim "migrations/036_backfill.py:42 — N+1 SELECT in transaction"`
- `/steelman:verify-claim "src/foo.py:100 — missing await on async call"`

If the input is missing file:line or claim description, refuse with a clear message.

## Procedure

### Step 1 — Parse inputs

Extract `file_path`, `line` (or `line_start:line_end`), and `claim_keywords` (the salient terms from the claim description — used for grep verification).

### Step 2 — File existence check

```bash
test -f "$FILE_PATH" || { echo "UNVERIFIABLE — file not found at $FILE_PATH"; exit 1; }
```

If file doesn't exist:
- Check git log for renames: `git log --diff-filter=R --follow -- $FILE_PATH`
- Check if it was deleted: `git log --diff-filter=D -- $FILE_PATH`
- Output `UNVERIFIABLE — file deleted in {hash}` or `UNVERIFIABLE — file renamed to {new_path}`

### Step 3 — Read cited lines + context

```bash
sed -n "$((LINE_START - 5)),$((LINE_END + 10))p" "$FILE_PATH"
```

If `LINE_END` not provided, use `LINE_START + 5`.

### Step 4 — Three mechanical checks

**Check A — Does the cited code match the claim description?**

If the claim mentions `function foo` but the cited lines show `function bar`, the claim is referencing wrong code. **`FALSIFIED — line:file citation does not match described code.`**

If the claim mentions specific syntax (`OR`, `await`, `try/except`, regex pattern) and that syntax is NOT present in the cited lines, **`FALSIFIED — described pattern not present.`**

**Check B — Is there a guarding `if` / `try` / `assert` clause that prevents the claimed failure?**

```bash
# Look 20 lines above the cited line for guarding patterns
sed -n "$((LINE_START - 20)),$LINE_START p" "$FILE_PATH" | grep -E "^\s*(if|elif|assert|try|with|except)" | head -5
```

If a guard is found that would prevent the claim's trigger condition, **`FALSIFIED — guarding clause at line N`**.

**Check C — Is the cited code reachable from production?**

```bash
# Extract the function/class name containing the cited line
ENCLOSING=$(awk -v line="$LINE_START" 'NR<=line && /^(def|class|async def) / { f=$0 } END { print f }' "$FILE_PATH" | sed 's/[():].*//' | awk '{print $NF}')

# Grep for callers (excluding test files)
grep -rn "$ENCLOSING" --include='*.py' | grep -v test_ | grep -v "$FILE_PATH:" | head -5
```

If zero callers found outside tests: **`UNVERIFIABLE — code may be dead; no production callers found.`** (Tag as `LATENT-NOT-FIRE`.)

### Step 5 — Output

If all three checks pass without falsifying:

```
CONFIRMED — claim is mechanically consistent with the source.
File: {file}
Lines: {range}
Cited code:
{code block}
Enclosing function/class: {name}
Production callers (sample): {list}

Note: this is mechanical verification only. The CLAIM may still be a false-positive on deeper analysis. For full triage with multi-AI jury + reproducible test, use /steelman:attack-finding.
```

If any check falsifies:

```
FALSIFIED — {which check failed}
File: {file}
Lines: {range}
Evidence:
{exact lines that prove falsification}

Recommendation: retire this claim from the backlog.
```

If unverifiable:

```
UNVERIFIABLE — {reason}
{evidence}

Recommendation: re-confirm with the original claim source (the file may have moved or the description may be stale). Or escalate to /steelman:attack-finding for deeper triage.
```

## Failure modes

1. **File path is relative without context** — Try resolving against the current `git rev-parse --show-toplevel`. If still not found, refuse.

2. **Line number is bogus** (negative, past EOF) — Refuse with `UNVERIFIABLE — line {N} out of range; file has {M} lines`.

3. **Claim describes a multi-file failure mode** — This skill only verifies single-file claims. Output `OUT-OF-SCOPE — multi-file claim; use /steelman:attack-finding instead`.

## Anti-patterns to reject

- ❌ Running this skill on a claim that has no `file:line` citation (it's not a claim, it's an opinion)
- ❌ Using this as substitute for `steelman:attack-finding` on high-stakes claims
- ❌ Trusting `CONFIRMED` as "the bug is real" (it just means "the cited code exists and matches the description" — the bug may still be a false-positive on deeper analysis)

## Auto-trigger conditions

This skill auto-triggers when:

- A claim with the shape `file:line — description` is pasted into the chat
- The user invokes `/steelman:verify-claim` directly
- Called from inside `steelman:attack-finding` as the first verification pass before spawning the jury

## Related skills

- `steelman:attack-finding` — full multi-AI jury triage (use after this skill returns CONFIRMED if the claim is high-stakes)
- `steelman:attack-fix` — for attacking a code CHANGE rather than a claim about existing code
