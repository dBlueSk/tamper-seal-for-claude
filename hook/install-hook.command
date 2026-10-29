#!/bin/bash
# Installs the tamper-seal hooks for Claude Code: automatic logging (after edits)
# and the guard (before edits).
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
3. Back up ~/.claude/settings.json, then add TWO hooks:
   - log: after Claude Code edits a file, log it
   - guard: before Claude Code edits a file that changed
     without a log entry, stop that edit once and ask
     Claude to re-read it first
4. Test both in a temporary folder (two tiny Claude Code runs)

Nothing else is changed. Undo with hook/remove-hook.command." "Install" || { echo "Cancelled. Nothing was changed."; finish 0; }

step "1/4  flock"
if command -v flock >/dev/null 2>&1; then echo "already installed"
elif command -v brew >/dev/null 2>&1; then HOMEBREW_NO_INSTALL_CLEANUP=1 brew install flock || { echo "FAIL: could not install flock"; finish 1; }
else echo "FAIL: flock not found. Install it (Linux: it ships with util-linux; macOS: brew install flock)."; finish 1; fi

step "2/4  copy files to $DEST"
mkdir -p "$DEST/scripts" "$DEST/log"
cp "$HERE/hook.sh" "$HERE/guard.sh" "$DEST/" && cp "$HERE/../scripts/evlog.sh" "$HERE/../scripts/watch.sh" "$HERE/../scripts/verify.sh" "$DEST/scripts/" && echo "done" || { echo "FAIL: copy"; finish 1; }

step "3/4  add the hooks to settings.json"
python3 - "$SETTINGS" <<'PY' || { echo "FAIL: settings not changed"; finish 1; }
import json, os, shutil, sys
p = sys.argv[1]
data = {}
if os.path.exists(p):
    try:
        data = json.load(open(p))
    except Exception as e:
        print("settings.json is not plain JSON, so I won't touch it:", e); sys.exit(3)
hooks = data.setdefault("hooks", {})
want = {"PostToolUse": "tamper-seal/hook.sh", "PreToolUse": "tamper-seal/guard.sh"}
missing = [ev for ev, script in want.items()
           if not any(script in h.get("command", "") for e in hooks.get(ev, []) for h in e.get("hooks", []))]
if not missing:
    print("both hooks already present, nothing to add"); sys.exit(0)
if os.path.exists(p):
    shutil.copy2(p, p + ".bak-tamper-seal"); print("backup saved:", p + ".bak-tamper-seal")
for ev in missing:
    hooks.setdefault(ev, []).append({"matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [{"type": "command", "command": 'bash "$HOME/.claude/' + want[ev] + '"'}]})
    print("added:", ev, "->", want[ev].split("/")[-1])
os.makedirs(os.path.dirname(p), exist_ok=True)
with open(p, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
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
awk -F'event=|seen=' '/^(SEAL|ok|ALERT) / { split($2, a, /[:. |]+/); split($3, b, /[:.]/);
  e = ((a[1]*60 + a[2])*60 + a[3])*1000 + a[4]; s = ((b[1]*60 + b[2])*60 + b[3])*1000 + b[4];
  d = s - e; if (d < 0) d += 86400000; if (n++ == 0 || d < mn) mn = d; if (d > mx) mx = d }
  END { if (n) printf "   (timing on this computer: logged -> seen in %d-%d ms)\n", mn, mx }' watch.txt
cp "$TS_DIR/events.log" chain-copy.log
E="PASS"
bash "$DEST/scripts/verify.sh" >/dev/null || E="FAIL (intact log reported as broken)"
sed -i.bak '1s/session=/session=forged-/' "$TS_DIR/events.log"
bash "$DEST/scripts/verify.sh" >/dev/null && E="FAIL (edited log reported as intact)"
cp chain-copy.log "$TS_DIR/events.log"

B="skipped (Claude Code not found)"
CLAUDE=$(command -v claude 2>/dev/null)
# The Claude desktop app on macOS ships its own Claude Code; use it if there's no claude on PATH.
[ -z "$CLAUDE" ] && CLAUDE=$(find "$HOME/Library/Application Support/Claude/claude-code" -maxdepth 6 -type f -name claude -perm -u+x 2>/dev/null | sort | tail -n 1)
if [ -n "$CLAUDE" ]; then
  "$CLAUDE" -p "Use the Write tool to create the file e2e.txt containing the word hello. Do nothing else." --allowedTools Write >/dev/null 2>&1
  if grep -q "e2e.txt" "$TS_DIR/events.log" 2>/dev/null; then B="PASS"; else B="FAIL (no log line; if Claude Code was just updated or not logged in, run the installer again)"; fi
fi
echo "B) real Claude Code edit is logged automatically: $B"

# C) the guard: blocks once after an outside change, then lets the retry through
echo "v1" > c.txt
printf '{"session_id":"selftest1","tool_input":{"file_path":"%s"}}' "$T/c.txt" | bash "$DEST/hook.sh"
gd() { printf '{"session_id":"selftest1","tool_input":{"file_path":"%s"}}' "$T/c.txt" | bash "$DEST/guard.sh" 2>/dev/null; echo $?; }
r1=$(gd); echo "outside" >> c.txt; r2=$(gd); r3=$(gd)
if [ "$r1 $r2 $r3" = "0 2 0" ]; then C="PASS"; else C="FAIL (got $r1 $r2 $r3, want 0 2 0)"; fi
echo "C) guard: unchanged file passes, outside change is blocked once, retry passes: $C"

# D) the guard with real Claude Code: blocked once, Claude re-reads, its edit keeps the outside change
D="skipped (Claude Code not found)"
if [ -n "$CLAUDE" ]; then
  "$CLAUDE" -p "Use the Write tool to create the file d.txt containing exactly one line: line one. Do nothing else." --allowedTools Write >/dev/null 2>&1
  echo "outside line" >> d.txt
  "$CLAUDE" -p "Use the Edit tool to replace the text 'line one' with 'line two' in d.txt. If a tool call is blocked, follow its message and try again. Do nothing else." --allowedTools Read,Edit >/dev/null 2>&1
  if grep -q "line two" d.txt && grep -q "outside line" d.txt && grep -q "session=guard-.*$T/d.txt" "$TS_DIR/events.log"; then D="PASS"
  else D="FAIL (file: $(tr '\n' '|' < d.txt))"; fi
fi
echo "D) real Claude Code is stopped once, re-reads, and keeps the outside change: $D"
echo "E) hash chain: intact log verifies, an edited past line is detected: $E"
cd / && rm -rf "$T"

echo
echo "Installed. Claude Code's own edits are logged, and edits to files changed"
echo "without a log entry are stopped once so Claude re-reads first. Log:"
echo "  $DEST/log/events.log"
echo "Check it any time: hook/check-log.command   Undo: hook/remove-hook.command"
finish 0
