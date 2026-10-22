#!/bin/bash
# Installs tamper-seal automatic logging for Claude Code.
# macOS: double-click (or run `bash hook/install-hook.command`). Linux: `bash hook/install-hook.command`.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.claude/local:/usr/bin:/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/tamper-seal"
SETTINGS="$HOME/.claude/settings.json"
step() { printf '\n== %s\n' "$*"; }
finish() { echo; read -r -p "Press Enter to close this window. " _; exit "${1:-0}"; }

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

confirm "Install tamper-seal hook" "tamper-seal for Claude Code will:

1. Install flock with Homebrew (if missing)
2. Copy tamper-seal into ~/.claude/tamper-seal
3. Back up ~/.claude/settings.json, then add ONE hook:
   after Claude Code edits or writes a file, log it
4. Test it in a temporary folder (one tiny Claude Code run)

Nothing else is changed. Undo with hook/remove-hook.command." "Install" || { echo "Cancelled. Nothing was changed."; finish 0; }

step "1/4  flock"
if command -v flock >/dev/null 2>&1; then echo "already installed"
elif command -v brew >/dev/null 2>&1; then HOMEBREW_NO_INSTALL_CLEANUP=1 brew install flock || { echo "FAIL: could not install flock"; finish 1; }
else echo "FAIL: flock not found. Install it (Linux: it ships with util-linux; macOS: brew install flock)."; finish 1; fi

step "2/4  copy files to $DEST"
mkdir -p "$DEST/scripts" "$DEST/log"
cp "$HERE/hook.sh" "$DEST/" && cp "$HERE/../scripts/evlog.sh" "$HERE/../scripts/watch.sh" "$DEST/scripts/" && echo "done" || { echo "FAIL: copy"; finish 1; }

step "3/4  add the hook to settings.json"
python3 - "$SETTINGS" <<'PY' || { echo "FAIL: settings not changed"; finish 1; }
import json, os, shutil, sys
p = sys.argv[1]
data = {}
if os.path.exists(p):
    try:
        data = json.load(open(p))
    except Exception as e:
        print("settings.json is not plain JSON, so I won't touch it:", e); sys.exit(3)
post = data.setdefault("hooks", {}).setdefault("PostToolUse", [])
if any("tamper-seal/hook.sh" in h.get("command", "") for e in post for h in e.get("hooks", [])):
    print("hook already present, nothing to add"); sys.exit(0)
if os.path.exists(p):
    shutil.copy2(p, p + ".bak-tamper-seal"); print("backup saved:", p + ".bak-tamper-seal")
post.append({"matcher": "Edit|Write|MultiEdit|NotebookEdit",
             "hooks": [{"type": "command", "command": 'bash "$HOME/.claude/tamper-seal/hook.sh"'}]})
os.makedirs(os.path.dirname(p), exist_ok=True)
with open(p, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
print("hook added")
PY

step "4/4  test (temporary folder, removed afterwards)"
T=$(mktemp -d); export TS_DIR="$T/log"; mkdir -p "$TS_DIR"; cd "$T" || finish 1
bash "$DEST/scripts/watch.sh" > watch.txt 2>/dev/null & WPID=$!
sleep 1
echo "draft" > a.txt
printf '{"session_id":"selftest1","tool_input":{"file_path":"%s"}}' "$T/a.txt" | bash "$DEST/hook.sh"; sleep 0.3
bash "$DEST/scripts/evlog.sh" check checked "$T/a.txt"; sleep 0.3
echo "sneaky" >> a.txt
bash "$DEST/scripts/evlog.sh" check checked "$T/a.txt"; sleep 0.5
{ pkill -P "$WPID"; kill "$WPID"; wait "$WPID"; } 2>/dev/null
got=$(grep -E '^(SEAL|ok|ALERT) ' watch.txt | cut -c1-5 | tr -d ' ' | paste -sd' ' -)
if [ "$got" = "SEAL ok ALERT" ]; then A="PASS"; else A="FAIL ($got)"; fi
echo "A) hook logs an edit, outside change is caught: $A"

B="skipped (Claude Code not found)"
CLAUDE=$(command -v claude 2>/dev/null)
# The Claude desktop app on macOS ships its own Claude Code; use it if there's no claude on PATH.
[ -z "$CLAUDE" ] && CLAUDE=$(find "$HOME/Library/Application Support/Claude/claude-code" -maxdepth 6 -type f -name claude -perm -u+x 2>/dev/null | sort | tail -n 1)
if [ -n "$CLAUDE" ]; then
  "$CLAUDE" -p "Use the Write tool to create the file e2e.txt containing the word hello. Do nothing else." --allowedTools Write >/dev/null 2>&1
  if grep -q "e2e.txt" "$TS_DIR/events.log" 2>/dev/null; then B="PASS"; else B="FAIL (no log line; if Claude Code was just updated or not logged in, run the installer again)"; fi
fi
echo "B) real Claude Code edit is logged automatically: $B"
cd / && rm -rf "$T"

echo
echo "Installed. From now on, Claude Code's own edits are logged to:"
echo "  $DEST/log/events.log"
echo "Check it any time: hook/check-log.command   Undo: hook/remove-hook.command"
finish 0
