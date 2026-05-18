#!/usr/bin/env bash
# steelman-suite hook: pre-push-attack-on-high-blast.sh
#
# PreToolUse hook for Bash with `git push`. Runs `steelman:attack-fix`
# (5-10 min, 3-reviewer jury) ONLY when the diff being pushed touches a path
# the operator has declared high-blast-radius.
#
# Routine pushes pay <1s overhead (path check + early exit).
#
# INSTALL: copy snippet into ~/.claude/settings.json (see ../docs/HOOKS.md).
#
# CONFIG:
#   STEELMAN_HIGH_BLAST_PATHS  — space-separated path patterns
#                                 (e.g. "migrations/ src/main.py")
#   STEELMAN_DISABLED          — any value silences the hook
#
# DECISION SEMANTICS:
#   - exit 0: allow push (default; pair found no blocker OR no high-blast files)
#   - exit 2: BLOCK push (loud message in stderr; operator must re-invoke
#               or pass --no-verify to override)

set -u

[ -n "${STEELMAN_DISABLED:-}" ] && exit 0
[ -z "${STEELMAN_HIGH_BLAST_PATHS:-}" ] && exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

# What's about to be pushed
LOCAL_HEAD=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null) || exit 0
REMOTE_HEAD=$(git -C "$REPO_ROOT" rev-parse '@{u}' 2>/dev/null || echo "")

if [ -z "$REMOTE_HEAD" ]; then
    # New branch — review last 3 commits to keep scope bounded
    DIFF_RANGE="HEAD~3..HEAD"
else
    DIFF_RANGE="$REMOTE_HEAD..HEAD"
fi

CHANGED=$(git -C "$REPO_ROOT" diff --name-only "$DIFF_RANGE" 2>/dev/null)
[ -z "$CHANGED" ] && exit 0

# Does any changed file match a high-blast pattern?
HIGH_BLAST_HIT=0
for pat in $STEELMAN_HIGH_BLAST_PATHS; do
    if echo "$CHANGED" | grep -qE "^$pat"; then
        HIGH_BLAST_HIT=1
        echo "[steelman] high-blast path matched: $pat" >&2
        break
    fi
done

if [ "$HIGH_BLAST_HIT" -eq 0 ]; then
    # No high-blast paths touched — fast exit
    exit 0
fi

CACHE_DIR="${STEELMAN_CACHE_DIR:-$REPO_ROOT/.steelman-cache}"
mkdir -p "$CACHE_DIR"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_DIR="$CACHE_DIR/attack-runs/$RUN_ID"
mkdir -p "$RUN_DIR"

# Capture the diff
git -C "$REPO_ROOT" diff "$DIFF_RANGE" > "$RUN_DIR/diff.patch"

echo ""
echo "🛡️  [steelman] high-blast diff detected → running attack-fix (5-10 min)"
echo "    This protects $STEELMAN_HIGH_BLAST_PATHS."
echo "    To skip just this push: STEELMAN_DISABLED=1 git push (or --no-verify if your remote uses pre-receive)"
echo "    Run dir: $RUN_DIR"
echo ""

# Run the 3-reviewer attack-fix synchronously. This IS blocking — by design,
# the user opted into this gate for these paths.
ATTACK_RUNNER="$(dirname "$0")/_attack_runner.sh"
if [ ! -x "$ATTACK_RUNNER" ]; then
    echo "[steelman] _attack_runner.sh not found at $ATTACK_RUNNER — allowing push" >&2
    exit 0
fi

"$ATTACK_RUNNER" "$RUN_DIR"
VERDICT=$?

case "$VERDICT" in
    0)
        echo "✅ [steelman] attack-fix: NO BLOCKERS — push proceeds"
        exit 0
        ;;
    2)
        echo "🚨 [steelman] attack-fix: BLOCKERS FOUND"
        echo "    Verdict: $RUN_DIR/verdict.md"
        echo "    To override: STEELMAN_DISABLED=1 git push"
        echo ""
        exit 2
        ;;
    *)
        echo "[steelman] attack-fix returned $VERDICT (degraded/timeout) — allowing push" >&2
        exit 0
        ;;
esac
