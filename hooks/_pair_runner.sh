#!/usr/bin/env bash
# steelman-suite — pair runner (called by post-edit-devils-pair.sh in background)
#
# Runs Claude and Codex in parallel on the captured diff. Aggregates verdicts.
# On disagreement, spawns a meta-judge subagent. Reports back via stderr +
# .steelman-cache/runs/<id>/verdict.json.

set -u

RUN_DIR="$1"
[ -d "$RUN_DIR" ] || exit 0

DIFF="$RUN_DIR/diff.patch"
[ -s "$DIFF" ] || exit 0

# ── Reviewer A (Claude, same-family) ────────────────────────────────────────
CLAUDE_OUT="$RUN_DIR/claude.txt"
CLAUDE_VERDICT="UNKNOWN"
CLAUDE_FINDING=""

# Strip implementer reasoning trace: remove `# Codex...`, `# Per operator...`,
# and any block-comment narration. Pure code only.
STRIPPED="$RUN_DIR/diff.stripped.patch"
grep -v -E '^\+\s*#\s*(Codex|Per operator|Audit|Fix:|Devil)' "$DIFF" > "$STRIPPED" || cp "$DIFF" "$STRIPPED"

if command -v claude >/dev/null 2>&1; then
    PROMPT="You are reviewer A on an adversarial code-review pair. Your job: find ONE concrete blocker in the diff below, or declare PASS. Time-box 50 seconds. No closing praise.

Output ONE of these on the first line:
  BLOCK: <one-line finding with file:line>
  PASS: <one-line justification that lists ≥2 specific attack vectors you ruled out>

Then 2-3 sentences elaborating. No more.

Diff:
$(cat "$STRIPPED")"

    timeout 70 claude -p "$PROMPT" --output-format text > "$CLAUDE_OUT" 2>>"$RUN_DIR/runner.log" &
    CLAUDE_PID=$!
fi

# ── Reviewer B (Codex, cross-family) ────────────────────────────────────────
CODEX_OUT="$RUN_DIR/codex.txt"
CODEX_VERDICT="UNKNOWN"
CODEX_FINDING=""

if command -v codex >/dev/null 2>&1; then
    PROMPT_B="You are a hostile reviewer at a competing team. Find ONE concrete blocker in the diff below, or declare PASS. Time-box 50 seconds. No softening.

Output ONE of these on the first line:
  BLOCK: <one-line finding with file:line>
  PASS: <one-line justification that lists ≥2 specific attack vectors you ruled out>

Then 2-3 sentences elaborating. No more.

Diff:
$(cat "$STRIPPED")"

    timeout 70 codex exec --skip-git-repo-check "$PROMPT_B" > "$CODEX_OUT" 2>>"$RUN_DIR/runner.log" &
    CODEX_PID=$!
fi

# ── Wait for both, capture verdicts ─────────────────────────────────────────
[ -n "${CLAUDE_PID:-}" ] && wait "$CLAUDE_PID" 2>/dev/null
[ -n "${CODEX_PID:-}" ] && wait "$CODEX_PID" 2>/dev/null

if [ -s "$CLAUDE_OUT" ]; then
    CLAUDE_LINE=$(head -1 "$CLAUDE_OUT")
    case "$CLAUDE_LINE" in
        BLOCK:*) CLAUDE_VERDICT="BLOCK"; CLAUDE_FINDING="${CLAUDE_LINE#BLOCK: }" ;;
        PASS:*)  CLAUDE_VERDICT="PASS";  CLAUDE_FINDING="${CLAUDE_LINE#PASS: }" ;;
    esac
fi

if [ -s "$CODEX_OUT" ]; then
    CODEX_LINE=$(head -1 "$CODEX_OUT")
    case "$CODEX_LINE" in
        BLOCK:*) CODEX_VERDICT="BLOCK"; CODEX_FINDING="${CODEX_LINE#BLOCK: }" ;;
        PASS:*)  CODEX_VERDICT="PASS";  CODEX_FINDING="${CODEX_LINE#PASS: }" ;;
    esac
fi

# ── Aggregate ───────────────────────────────────────────────────────────────
PAIR_RESULT=""
case "${CLAUDE_VERDICT}/${CODEX_VERDICT}" in
    "PASS/PASS")
        PAIR_RESULT="PAIR-PASSED"
        ;;
    "BLOCK/BLOCK")
        PAIR_RESULT="BLOCK-BOTH"
        ;;
    "BLOCK/PASS" | "PASS/BLOCK")
        PAIR_RESULT="DISAGREEMENT"
        ;;
    *)
        PAIR_RESULT="DEGRADED-PAIR"
        ;;
esac

# ── Meta-judge on disagreement (fresh Claude context, ~30s) ────────────────
META_OUT="$RUN_DIR/meta.txt"
META_VERDICT=""
if [ "$PAIR_RESULT" = "DISAGREEMENT" ] && command -v claude >/dev/null 2>&1; then
    META_PROMPT="You are the meta-judge in an adversarial code review. Two independent reviewers disagreed about whether this diff should ship.

Reviewer A (Claude, same-family): ${CLAUDE_VERDICT} — ${CLAUDE_FINDING}
Full A response: $(cat "$CLAUDE_OUT" | head -10)

Reviewer B (Codex, cross-family): ${CODEX_VERDICT} — ${CODEX_FINDING}
Full B response: $(cat "$CODEX_OUT" | head -10)

You see neither reviewer's reasoning trace beyond the above. You also see the raw diff.

Your job: decide. Output ONE of these on the first line, then 2-3 sentence justification:
  BLOCK: <one-line finding with file:line>
  PASS: <one-line justification>
  NEEDS-OPERATOR: <one-line description of the genuine ambiguity>

Diff:
$(cat "$STRIPPED")"

    timeout 45 claude -p "$META_PROMPT" --output-format text > "$META_OUT" 2>>"$RUN_DIR/runner.log"
    if [ -s "$META_OUT" ]; then
        META_LINE=$(head -1 "$META_OUT")
        case "$META_LINE" in
            BLOCK:*)          META_VERDICT="META-BLOCK: ${META_LINE#BLOCK: }" ;;
            PASS:*)           META_VERDICT="META-PASS: ${META_LINE#PASS: }" ;;
            NEEDS-OPERATOR:*) META_VERDICT="META-OPERATOR: ${META_LINE#NEEDS-OPERATOR: }" ;;
        esac
    fi
fi

# ── Write structured verdict ───────────────────────────────────────────────
{
    echo "{"
    echo "  \"pair_result\": \"$PAIR_RESULT\","
    echo "  \"claude\":      { \"verdict\": \"$CLAUDE_VERDICT\", \"finding\": \"$(echo "$CLAUDE_FINDING" | sed 's/"/\\"/g')\" },"
    echo "  \"codex\":       { \"verdict\": \"$CODEX_VERDICT\",  \"finding\": \"$(echo "$CODEX_FINDING"  | sed 's/"/\\"/g')\" },"
    echo "  \"meta_judge\":  \"$(echo "$META_VERDICT" | sed 's/"/\\"/g')\","
    echo "  \"run_dir\":     \"$RUN_DIR\""
    echo "}"
} > "$RUN_DIR/verdict.json"

# ── Surface to operator only when there's something to say ─────────────────
case "$PAIR_RESULT" in
    PAIR-PASSED)
        # Silent. Don't dérange. The fact that we ran is logged in .steelman-cache.
        ;;
    BLOCK-BOTH)
        echo ""
        echo "🚨 [steelman] BLOCK — оба ревьюера нашли блокер в последних изменениях:"
        echo "   Claude: $CLAUDE_FINDING"
        echo "   Codex:  $CODEX_FINDING"
        echo "   Подробности: $RUN_DIR/"
        echo "" >&2
        ;;
    DISAGREEMENT)
        echo ""
        if [ -n "$META_VERDICT" ]; then
            echo "⚖️ [steelman] разногласие → судья решил: $META_VERDICT"
            echo "   Claude was: $CLAUDE_VERDICT — $CLAUDE_FINDING"
            echo "   Codex was:  $CODEX_VERDICT — $CODEX_FINDING"
        else
            echo "⚖️ [steelman] разногласие (судья недоступен):"
            echo "   Claude: $CLAUDE_VERDICT — $CLAUDE_FINDING"
            echo "   Codex:  $CODEX_VERDICT — $CODEX_FINDING"
        fi
        echo "   Подробности: $RUN_DIR/" >&2
        echo "" >&2
        ;;
    DEGRADED-PAIR)
        echo "[steelman] pair degraded (одна сторона не вернула вердикт) — детали $RUN_DIR/" >&2
        ;;
esac

exit 0
