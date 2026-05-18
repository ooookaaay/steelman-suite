#!/usr/bin/env bash
# steelman-suite hook: post-edit-devils-pair.sh
#
# PostToolUse hook for Edit / Write tools. Background-triggers
# `steelman:devils-pair` (Codex + Claude in parallel, ~60s) when cumulative
# uncommitted change reaches the LOC threshold.
#
# DESIGN PRINCIPLES (per operator binding feedback_no_overengineering +
# the SOTA-2026 methodology research):
# - Fires in BACKGROUND. Never blocks the agent's next tool call.
# - LOC threshold gate (default 25). Small changes get skipped.
# - One pair per ~5 minutes max — debounced via stamp file.
# - Codex + Claude run INDEPENDENTLY (MARS pattern, no cross-talk).
# - Disagreement → meta-judge subagent decides; output to ../.steelman-cache/.
# - Reports back via OSC9 + structured stdout the harness can render.
#
# INSTALL: copy this snippet into ~/.claude/settings.json hooks array:
#
#   {
#     "event": "PostToolUse",
#     "matcher": "Edit|Write",
#     "command": "/path/to/steelman-suite/hooks/post-edit-devils-pair.sh"
#   }
#
# Or — operator binding feedback_use_codex_not_askquestion — wrap via
# the existing update-config skill if it's not in settings yet.
#
# CONFIG (env vars):
#   STEELMAN_PAIR_LOC_THRESHOLD   — default 25; minimum cumulative LOC delta
#                                    to trigger the pair
#   STEELMAN_PAIR_DEBOUNCE_S      — default 300; suppress repeats within window
#   STEELMAN_DISABLED             — any non-empty value silences this hook entirely
#   STEELMAN_CACHE_DIR            — default $REPO_ROOT/.steelman-cache
#
# EXIT CODES:
#   0  — always (this hook is non-blocking by contract; failures log silently)
#
# DEPENDENCIES: bash, git, awk, codex CLI (optional — falls back to Claude-only
# pair if not available), claude CLI (mandatory).

set -u  # not -e — we never want to fail the parent tool call

[ -n "${STEELMAN_DISABLED:-}" ] && exit 0

LOC_THRESHOLD="${STEELMAN_PAIR_LOC_THRESHOLD:-25}"
DEBOUNCE_S="${STEELMAN_PAIR_DEBOUNCE_S:-300}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
CACHE_DIR="${STEELMAN_CACHE_DIR:-$REPO_ROOT/.steelman-cache}"
mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0

STAMP="$CACHE_DIR/.last-pair-run"
NOW=$(date +%s)
if [ -f "$STAMP" ]; then
    LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
    AGE=$((NOW - LAST))
    if [ "$AGE" -lt "$DEBOUNCE_S" ]; then
        # Debounced — skip
        exit 0
    fi
fi

# Cumulative uncommitted LOC delta (added + deleted, both staged and unstaged)
LOC=$(cd "$REPO_ROOT" && git diff --numstat HEAD 2>/dev/null | awk '
    { added += $1; deleted += $2 }
    END { print added + deleted }
')
LOC=${LOC:-0}

if [ "$LOC" -lt "$LOC_THRESHOLD" ]; then
    # Change too small — skip
    exit 0
fi

# Mark this run BEFORE spawning so concurrent Edit/Write tools don't double-fire.
echo "$NOW" > "$STAMP"

# Spawn the pair runner in a fully-detached background process. The parent
# Claude Code session does NOT wait. Output streams to a per-run log; on
# completion the runner emits OSC9 + structured stdout for the harness.
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_DIR="$CACHE_DIR/runs/$RUN_ID"
mkdir -p "$RUN_DIR"

# Capture the current diff at this moment — the pair reviews THIS snapshot,
# not whatever state evolves while it's running.
git -C "$REPO_ROOT" diff HEAD > "$RUN_DIR/diff.patch" 2>/dev/null

PAIR_RUNNER="$(dirname "$0")/_pair_runner.sh"
if [ ! -x "$PAIR_RUNNER" ]; then
    # Runner missing — log and exit
    echo "[steelman-hook] _pair_runner.sh not found at $PAIR_RUNNER — skipping" \
        >> "$RUN_DIR/hook.log"
    exit 0
fi

# nohup + & + disown — fully detach so parent session never blocks
nohup "$PAIR_RUNNER" "$RUN_DIR" </dev/null >>"$RUN_DIR/runner.log" 2>&1 &
disown 2>/dev/null || true

# Notify the operator non-intrusively via stderr (Claude Code surfaces this
# as an info message, not a tool error).
echo "[steelman] devils-pair launched in background (LOC=$LOC, run=$RUN_ID)" >&2

exit 0
