#!/bin/bash
# Shows whether the tamper-seal hook is installed and what it has logged.
S="$HOME/.claude/settings.json"
L="$HOME/.claude/tamper-seal/log/events.log"
echo "== hooks in settings.json"
for h in hook guard; do if grep -q "tamper-seal/$h.sh" "$S" 2>/dev/null; then echo "$h: installed"; else echo "$h: NOT installed"; fi; done
echo
echo "== log: $L"
if [ -s "$L" ]; then
  n=$(wc -l < "$L" | tr -d ' ')
  cc=$(grep -c "$(printf '\t')session=cc-" "$L")
  gb=$(grep -c "$(printf '\t')session=guard-" "$L")
  echo "$n entries; $cc logged automatically by Claude Code (session=cc-...);"
  echo "$gb edits stopped once by the guard (session=guard-...)"
  echo
  echo "== latest 10 (UTC time, session, action, file)"
  tail -n 10 "$L" | awk -F'\t' '{ delete v; for (i = 1; i <= NF; i++) { p = index($i, "="); v[substr($i, 1, p - 1)] = substr($i, p + 1) }
    printf "%s  %-12s %-9s %s\n", substr(v["ts"], 12, 8), v["session"], v["action"], v["target"] }'
else
  echo "empty so far: no Claude Code edit has been logged yet"
fi
echo
echo "== hash chain"
if [ -f "$HOME/.claude/tamper-seal/scripts/verify.sh" ]; then
  TS_DIR="$HOME/.claude/tamper-seal/log" bash "$HOME/.claude/tamper-seal/scripts/verify.sh"
else echo "verify.sh not installed (run the installer again)"; fi
echo
read -r -p "Press Enter to close. " _
