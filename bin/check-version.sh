#!/usr/bin/env bash
# steelman-suite — version-check.
#
# Idea borrowed from GSD's bin/check-latest-version.cjs: the remote location
# is a CONSTANT in code, not a runtime choice — the executing model cannot
# point it at the wrong place.
#
# Efficiency contract (this suite's whole ethos — never waste time):
#   - Throttled: one network call per 24h, max. Every other invocation is a
#     local file read (<1ms).
#   - Never blocks: a stale cache is refreshed in a BACKGROUND process; the
#     skill that called this never waits on the network.
#   - Never errors loudly: offline / no curl / parse failure → silent, prints
#     the "none" line and exits 0.
#
# Output — exactly one line on stdout:
#   STEELMAN_UPDATE available: installed vX, latest vY — run: git -C <root> pull
#   STEELMAN_UPDATE none (vX)
#
# A skill runs this and surfaces the line ONLY when it starts "available".
set -u

_SUITE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || exit 0
_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/steelman-suite"
_CACHE_FILE="$_CACHE_DIR/version-check"
_TTL=86400  # 24h
# Hardcoded — do not parameterise. The point is that the source is fixed.
_RAW_URL="https://raw.githubusercontent.com/ooookaaay/steelman-suite/main/plugin.json"

_ver_from_json() {
  grep -m1 '"version"' "$1" 2>/dev/null \
    | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}

_LOCAL="$(_ver_from_json "$_SUITE_ROOT/plugin.json")"
[ -z "$_LOCAL" ] && exit 0  # cannot determine installed version — stay silent

mkdir -p "$_CACHE_DIR" 2>/dev/null || true

# Background refresh — fetch the remote version and rewrite the cache.
# Runs detached; the caller never waits on it.
_refresh() {
  local body remote fetch
  if command -v curl >/dev/null 2>&1; then
    fetch="curl -fsS -m 8"
  elif command -v wget >/dev/null 2>&1; then
    fetch="wget -qO- -T 8"
  else
    return 0
  fi
  body="$($fetch "$_RAW_URL" 2>/dev/null)" || return 0
  remote="$(printf '%s' "$body" | grep -m1 '"version"' \
    | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  [ -z "$remote" ] && return 0  # parse fail — keep the old cache
  printf '%s %s\n' "$(date +%s)" "$remote" > "$_CACHE_FILE.tmp" 2>/dev/null \
    && mv "$_CACHE_FILE.tmp" "$_CACHE_FILE" 2>/dev/null
}

_LATEST=""
if [ -f "$_CACHE_FILE" ]; then
  read -r _TS _LATEST < "$_CACHE_FILE" 2>/dev/null || true
  if [ $(( $(date +%s) - ${_TS:-0} )) -ge "$_TTL" ]; then
    ( _refresh ) >/dev/null 2>&1 &  # stale-while-revalidate: refresh for NEXT run
    disown 2>/dev/null || true
  fi
else
  ( _refresh ) >/dev/null 2>&1 &     # first run — no cache; fetch for next time
  disown 2>/dev/null || true
fi

if [ -n "$_LATEST" ] && [ "$_LATEST" != "$_LOCAL" ]; then
  _NEWER="$(printf '%s\n%s\n' "$_LOCAL" "$_LATEST" | sort -V 2>/dev/null | tail -1)"
  if [ "$_NEWER" = "$_LATEST" ]; then
    echo "STEELMAN_UPDATE available: installed v$_LOCAL, latest v$_LATEST — run: git -C $_SUITE_ROOT pull"
    exit 0
  fi
fi
echo "STEELMAN_UPDATE none (v$_LOCAL)"
