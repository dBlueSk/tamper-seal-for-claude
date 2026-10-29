#!/usr/bin/env bash
# tamper-seal hook for Claude Code: logs Claude's own file edits as "modified".
# It never blocks or slows the tool call: no output, always exit 0.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
HERE="$HOME/.claude/tamper-seal"
export TS_DIR="${TS_DIR:-$HERE/log}"
{
  input=$(cat)
  # Session label: first 8 characters of the session ID, plus "-sub-<agent ID>" for a sub-agent's edit.
  sid=$(printf '%s' "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin); a=d.get("agent_id"); print((d.get("session_id") or "unknown")[:8] + ("-sub-" + str(a)[:8] if a else ""))')
  path=$(printf '%s' "$input" | python3 -c 'import json,sys; t=json.load(sys.stdin).get("tool_input") or {}; print(t.get("file_path") or t.get("notebook_path") or "")')
  mkdir -p "$TS_DIR"
  [ -n "$path" ] && bash "$HERE/scripts/evlog.sh" "cc-$sid" modified "$path"
} >/dev/null 2>&1
exit 0
