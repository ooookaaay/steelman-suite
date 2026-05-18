# Auto-trigger hooks

By default the suite is invocation-only. Hooks turn it into a background guard.
The pair hook is **opt-in but recommended** — it's the workhorse.

## TL;DR — copy-pasteable `~/.claude/settings.json`

Drop this into `~/.claude/settings.json` (merge with existing keys; don't overwrite). Replace `/ABSOLUTE/PATH/TO/steelman-suite` with your clone path.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "/ABSOLUTE/PATH/TO/steelman-suite/hooks/post-edit-devils-pair.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "pattern": "^git push",
        "hooks": [
          {
            "type": "command",
            "command": "/ABSOLUTE/PATH/TO/steelman-suite/hooks/pre-push-attack-on-high-blast.sh"
          }
        ]
      }
    ]
  },
  "env": {
    "STEELMAN_PAIR_LOC_THRESHOLD": "25",
    "STEELMAN_PAIR_DEBOUNCE_S": "300",
    "STEELMAN_HIGH_BLAST_PATHS": "migrations/ src/main.py"
  }
}
```

**Shape gotchas** (Claude Code rejects silently if you get these wrong):

- `hooks` is an OBJECT, keyed by event name (`PostToolUse`, `PreToolUse`, `Stop`, `SubagentStop`, etc.) — NOT an array.
- Each event maps to an ARRAY of matcher-groups.
- Each matcher-group has a `matcher` regex (matched against tool name) and a `hooks` ARRAY of `{type, command}` entries.
- `command` MUST be an absolute path (`~` is NOT expanded; `$HOME` may or may not be — use the literal path).
- `pattern` (PreToolUse on Bash) is matched against the full command string.
- After editing, run `/reload-plugins` in every live Claude Code session — settings.json is loaded at session start.

If the hook never fires, check `~/.claude/logs/*.log` for `hook command failed:` lines — most issues are wrong path or non-executable script (`chmod +x hooks/*.sh`).

## The default-recommended hook: pair-on-edit

Adds `~60 seconds in the background` whenever your cumulative uncommitted
diff crosses a threshold (default 25 LOC). Runs Claude + Codex independently,
shows you a message ONLY when there's something to say.

### How the spar-and-resolve works

When the hook fires, this is the runtime contract:

```
  Edit / Write tool finishes
            ↓
  hook checks LOC threshold (≥25 by default)
            ↓
  background pair starts (returns control to Claude IMMEDIATELY)
            ↓
  ┌──────────────────────┬──────────────────────┐
  │ Claude reviewer       │ Codex reviewer        │   (parallel, ~50s each)
  │ same-family critic    │ cross-family critic   │   (no cross-talk — MARS pattern)
  │ stripped diff input   │ stripped diff input   │
  └──────────────────────┴──────────────────────┘
            ↓
   aggregate verdicts:
            ↓
  ┌─────────────────────────┬──────────────────────────┬──────────────────┐
  │ BOTH PASS               │ BOTH BLOCK                │ DISAGREE          │
  │ silent log,             │ loud message in chat:      │ meta-judge fires  │
  │ no operator interrupt   │ "STEELMAN: блокер найден" │ (Claude in fresh  │
  │                         │                            │ context, ~30s)    │
  │                         │                            │ → final verdict   │
  └─────────────────────────┴──────────────────────────┴──────────────────┘
```

This IS the "Codex argues with Claude, Claude argues with Codex, and somehow
it gets resolved" you wanted — but as **MARS pattern** (independent reviews +
meta-judge on conflict), not as direct debate.

Per the SOTA-2026 research dossier shipped with this suite, free-MAD (direct
back-and-forth debate) does NOT beat single-agent on code review (per
[_Stop Overvaluing MAD_, arxiv 2502.08788](https://arxiv.org/abs/2502.08788)).
MARS — independent reviewers + a meta-reviewer — is the architecture top
shops actually use ([MARS, arxiv 2509.12054](https://arxiv.org/abs/2509.12054)).

### Install

Add to `~/.claude/settings.json` `hooks` array:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/steelman-suite/hooks/post-edit-devils-pair.sh"
          }
        ]
      }
    ]
  }
}
```

Adjust the path to wherever you cloned the suite.

### Configuration via env vars (no settings.json edit needed)

```bash
# Threshold for triggering (default 25 LOC)
export STEELMAN_PAIR_LOC_THRESHOLD=25

# Debounce — don't re-fire within N seconds (default 300 = 5 min)
export STEELMAN_PAIR_DEBOUNCE_S=300

# Kill switch — set this to silence the hook entirely without removing it
export STEELMAN_DISABLED=1

# Cache directory (default $REPO_ROOT/.steelman-cache)
export STEELMAN_CACHE_DIR=/tmp/steelman-cache

# Add the cache dir to your .gitignore — these runs persist for forensics
echo '.steelman-cache/' >> .gitignore
```

### Latency budget (worst case)

| Scenario | Latency added to your flow |
|---|---|
| Small edit (<25 LOC) | 0s (hook checks threshold and exits) |
| Within debounce window (<5 min from last pair) | 0s |
| Pair-passed (both agree code is fine) | 0s (silent) |
| Pair-blocked (both find a real issue) | 0s in foreground, message appears in stderr ~70s later |
| Pair-disagreed (need meta-judge) | 0s in foreground, message appears ~100s later |

**Foreground latency: always 0s.** The hook never blocks. Worst case the
operator sees the verdict 1-2 minutes after the edit landed.

## Optional: pre-push attack-fix on high-blast paths

This is the heavier hook. Default-disabled. Fires `steelman:attack-fix` (3-reviewer
jury, 5-10 min) ONLY when the diff touches a path you've declared high-blast-radius.

### Install

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "pattern": "^git push",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/steelman-suite/hooks/pre-push-attack-on-high-blast.sh"
          }
        ]
      }
    ]
  }
}
```

```bash
# Required: paths that, when modified, justify the 5-10 min attack-fix cost
export STEELMAN_HIGH_BLAST_PATHS="migrations/ src/main.py src/processing/article_processor.py"
```

If your push doesn't touch any path in the list, the hook exits in <1s and the
push proceeds normally. This is the right trade-off for migrations + publish-path
code — paths where a regression costs hours of operator time, not minutes.

## Disabling

Three ways:

1. `export STEELMAN_DISABLED=1` — kills all steelman hooks instantly
2. Remove from `~/.claude/settings.json` hooks array
3. `rm -rf /path/to/steelman-suite` — nuclear

## Why opt-in by default

Per the suite's design principle (and the operator binding feedback_no_overengineering):
*adversarial review is only valuable when its findings are real AND its latency is
acceptable*. Ambient critics suffer vigilance decrement (Atomic Robot 2024) and the
3-reviewer jury isn't free. The 25-LOC threshold + 5-min debounce + background
execution makes the pair-on-edit hook cheap enough that we recommend turning it on;
but the choice stays with the operator.
