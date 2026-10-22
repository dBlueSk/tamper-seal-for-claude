#!/bin/bash
# Shows whether the tamper-seal hook is installed and what it has logged.
S="$HOME/.claude/settings.json"
L="$HOME/.claude/tamper-seal/log/events.log"
echo "== hook in settings.json"
if grep -q "tamper-seal/hook.sh" "$S" 2>/dev/null; then echo "installed"; else echo "NOT installed"; fi
echo
echo "== log: $L"
if [ -s "$L" ]; then
  n=$(wc -l < "$L" | tr -d ' ')
  cc=$(grep -c "$(printf '\t')session=cc-" "$L")
  echo "$n entries; $cc written automatically by Claude Code (session=cc-...)"
  echo
  echo "== latest 10 (UTC time, session, action, file)"
  tail -n 10 "$L" | awk -F'\t' '{ delete v; for (i = 1; i <= NF; i++) { p = index($i, "="); v[substr($i, 1, p - 1)] = substr($i, p + 1) }
    printf "%s  %-12s %-9s %s\n", substr(v["ts"], 12, 8), v["session"], v["action"], v["target"] }'
else
  echo "empty so far: no Claude Code edit has been logged yet"
fi
echo
read -r -p "Press Enter to close. " _
