#!/usr/bin/env bash
# steelman-suite — attack-fix runner (called by pre-push-attack-on-high-blast.sh)
#
# Synchronous 3-reviewer jury (Claude + Codex + meta-judge).
# Returns:
#   0 — no blockers found
#   2 — at least one blocker confirmed
#   1 — degraded / timeout / config error (caller treats as soft-allow)

set -u

RUN_DIR="$1"
[ -d "$RUN_DIR" ] || exit 1

DIFF="$RUN_DIR/diff.patch"
[ -s "$DIFF" ] || exit 1

# ── Strip implementer reasoning trace ──────────────────────────────────────
STRIPPED="$RUN_DIR/diff.stripped.patch"
grep -v -E '^\+\s*#\s*(Codex|Per operator|Audit|Fix:|Devil|Claude)' "$DIFF" > "$STRIPPED" || cp "$DIFF" "$STRIPPED"

# ── Spawn reviewers in parallel ─────────────────────────────────────────────
A_OUT="$RUN_DIR/a-claude.json"
B_OUT="$RUN_DIR/b-reviewer.json"
REVIEWER_B_ENGINE=""

REVIEWER_PROMPT='You are reviewer on an adversarial code-review jury. Find concrete blockers, not style nits.

Output strict JSON only (no markdown fences, no preamble):
{
  "findings": [
    {"file": "...", "lines": "N-M", "verdict": "REAL|UNCLEAR|FALSE", "attack": "concrete failure mode", "test": "paste-ready reproducer"}
  ]
}

If you find no real bugs after a thorough adversarial pass, return {"findings":[]} BUT only after ruling out at least 3 specific attack vectors (null/empty input, concurrency/race, error-path state corruption, off-by-one, TOCTOU, resource leak, cross-file invariant break).

The diff (no commit message, no design context provided — by design):
'

# Hostile cross-stance prompt for reviewer B — used both by Codex and the
# dialectical-bootstrap fallback (second independent Claude pass).
HOSTILE_PROMPT='You are a hostile reviewer at a competing team. Your job is to find every concrete blocker in this diff. Find concrete blockers, not style nits.

Output strict JSON only (no markdown fences, no preamble):
{
  "findings": [
    {"file": "...", "lines": "N-M", "verdict": "REAL|UNCLEAR|FALSE", "attack": "concrete failure mode", "test": "paste-ready reproducer"}
  ]
}

If you find no real bugs after a thorough adversarial pass, return {"findings":[]} BUT only after ruling out at least 3 specific attack vectors (null/empty input, concurrency/race, error-path state corruption, off-by-one, TOCTOU, resource leak, cross-file invariant break).

The diff (no commit message, no design context provided — by design):
'

if command -v claude >/dev/null 2>&1; then
    timeout 360 claude -p "$REVIEWER_PROMPT
$(cat "$STRIPPED")" --output-format text > "$A_OUT" 2>>"$RUN_DIR/runner.log" &
    A_PID=$!
fi

if command -v codex >/dev/null 2>&1; then
    timeout 360 codex exec --skip-git-repo-check "$HOSTILE_PROMPT
$(cat "$STRIPPED")" > "$B_OUT" 2>>"$RUN_DIR/runner.log" &
    B_PID=$!
    REVIEWER_B_ENGINE="Codex"
elif command -v claude >/dev/null 2>&1; then
    # Dialectical bootstrap: second independent Claude pass with hostile cross-stance
    # framing. Same model, different adversarial angle, no cross-talk with Reviewer A.
    timeout 360 claude -p "$HOSTILE_PROMPT
$(cat "$STRIPPED")" --output-format text > "$B_OUT" 2>>"$RUN_DIR/runner.log" &
    B_PID=$!
    REVIEWER_B_ENGINE="Claude, cross-stance"
fi

[ -n "${A_PID:-}" ] && wait "$A_PID" 2>/dev/null
[ -n "${B_PID:-}" ] && wait "$B_PID" 2>/dev/null

# ── Parse findings — strict JSON, lenient extraction ───────────────────────
A_FINDINGS=$(python3 -c '
import json, sys, re
try:
    txt = open("'"$A_OUT"'").read()
    m = re.search(r"\{.*\}", txt, re.DOTALL)
    if m:
        j = json.loads(m.group())
        print(len([f for f in j.get("findings", []) if f.get("verdict") == "REAL"]))
    else:
        print("0")
except Exception:
    print("0")
' 2>/dev/null)
A_FINDINGS=${A_FINDINGS:-0}

B_FINDINGS=$(python3 -c '
import json, sys, re
try:
    txt = open("'"$B_OUT"'").read()
    m = re.search(r"\{.*\}", txt, re.DOTALL)
    if m:
        j = json.loads(m.group())
        print(len([f for f in j.get("findings", []) if f.get("verdict") == "REAL"]))
    else:
        print("0")
except Exception:
    print("0")
' 2>/dev/null)
B_FINDINGS=${B_FINDINGS:-0}

# ── Aggregate ───────────────────────────────────────────────────────────────
{
    echo "# Attack-fix verdict — $(basename "$RUN_DIR")"
    echo ""
    echo "## Reviewer A (Claude)"
    echo ""
    echo '```'
    head -100 "$A_OUT" 2>/dev/null || echo "(no output)"
    echo '```'
    echo ""
    echo "## Reviewer B (${REVIEWER_B_ENGINE:-cross-stance})"
    echo ""
    echo '```'
    head -100 "$B_OUT" 2>/dev/null || echo "(no output)"
    echo '```'
    echo ""
    echo "## Summary"
    echo "- Reviewer A REAL findings: $A_FINDINGS"
    echo "- Reviewer B (${REVIEWER_B_ENGINE:-cross-stance}) REAL findings: $B_FINDINGS"
} > "$RUN_DIR/verdict.md"

# Decision policy:
# - Both reviewers find ≥1 REAL with overlapping file:line → BLOCK
# - Only one reviewer finds REAL → soft-block (operator decides) — return 2
# - Neither finds REAL → PASS
TOTAL_REAL=$((A_FINDINGS + B_FINDINGS))

if [ "$TOTAL_REAL" -ge 1 ]; then
    exit 2
fi
exit 0
