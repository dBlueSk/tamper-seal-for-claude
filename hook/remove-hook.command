#!/bin/bash
# Removes the tamper-seal hook from Claude Code (macOS: double-click; Linux: bash hook/remove-hook.command).
SETTINGS="$HOME/.claude/settings.json"
confirm() {  # $1 = title, $2 = message, $3 = button
  if [ -n "${SKIP_DIALOG:-}" ]; then return 0; fi
  if command -v osascript >/dev/null 2>&1; then
    osascript - "$1" "$2" "$3" >/dev/null 2>&1 <<'AS'
on run argv
  display dialog (item 2 of argv) with title (item 1 of argv) buttons {"Cancel", item 3 of argv} default button (item 3 of argv) cancel button "Cancel"
end run
AS
  else
    printf '%s\n\n%s\n\n' "$1" "$2"; read -r -p "$3? [y/N] " a; [ "$a" = y ] || [ "$a" = Y ]
  fi
}

confirm "Remove tamper-seal hook" "Remove the tamper-seal hooks (log + guard) from Claude Code and delete ~/.claude/tamper-seal (including its log)?" "Remove" \
  || { echo "Cancelled. Nothing was changed."; read -r -p "Press Enter to close. " _; exit 0; }
python3 - "$SETTINGS" <<'PY'
import json, os, sys
p = sys.argv[1]
if not os.path.exists(p): print("no settings.json, nothing to remove"); sys.exit(0)
data = json.load(open(p))
hooks = data.get("hooks", {})
removed = 0
for ev in ("PostToolUse", "PreToolUse"):
    entries = hooks.get(ev, [])
    keep = [e for e in entries if not any(x in h.get("command", "") for h in e.get("hooks", [])
                                          for x in ("tamper-seal/hook.sh", "tamper-seal/guard.sh"))]
    removed += len(entries) - len(keep)
    if keep: hooks[ev] = keep
    else: hooks.pop(ev, None)
if not removed: print("tamper-seal hooks not found in settings.json")
else:
    if not hooks: data.pop("hooks", None)
    with open(p, "w") as f: json.dump(data, f, indent=2); f.write("\n")
    print("removed", removed, "tamper-seal hook(s) from settings.json")
PY
rm -rf "$HOME/.claude/tamper-seal" && echo "deleted ~/.claude/tamper-seal"
echo "flock stays installed; remove it with: brew uninstall flock"
read -r -p "Press Enter to close. " _
