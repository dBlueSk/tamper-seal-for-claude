#!/usr/bin/env bash
# tamper-seal hook for Claude Code: logs Claude's own file edits as "modified".
# It never blocks or slows the tool call: no output, always exit 0.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
HERE="$HOME/.claude/tamper-seal"
export TS_DIR="${TS_DIR:-$HERE/log}"
{
  input=$(cat)
  sid=$(printf '%s' "$input" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("session_id") or "unknown")[:8])')
  path=$(printf '%s' "$input" | python3 -c 'import json,sys; t=json.load(sys.stdin).get("tool_input") or {}; print(t.get("file_path") or t.get("notebook_path") or "")')
  mkdir -p "$TS_DIR"
  [ -n "$path" ] && bash "$HERE/scripts/evlog.sh" "cc-$sid" modified "$path"
} >/dev/null 2>&1
exit 0
