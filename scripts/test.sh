#!/usr/bin/env bash
# Self-test for tamper-seal. Runs in a temporary folder; touches nothing else.
# Usage: bash scripts/test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)

# Check requirements once, up front.
command -v flock >/dev/null 2>&1 || { echo "missing: flock (macOS: brew install flock)"; exit 1; }
command -v awk   >/dev/null 2>&1 || { echo "missing: awk"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export TS_DIR="$TMP/log"; mkdir -p "$TS_DIR" "$TMP/src" "$TMP/tests"
cd "$TMP" || exit 1

bash "$HERE/watch.sh" > out.txt 2>/dev/null &
WPID=$!
sleep 1
log() { bash "$HERE/evlog.sh" "$@"; sleep 0.3; }

# 1) basic demo
echo "draft v1" > notes.txt
log main-1 modified notes.txt
log main-1 checked  notes.txt
echo "sneaky edit" >> notes.txt
log sub-2  checked  notes.txt
log main-1 modified notes.txt
log sub-2  checked  notes.txt
# 2) filename with spaces must not collide with another "my ..." file
echo a > "my notes.txt"; echo b > "my plan.txt"
log main-1 modified "my notes.txt"
log main-1 modified "my plan.txt"
log sub-2  checked  "my notes.txt"
# 3) same name in different folders must stay separate
echo one > src/config.py; echo two > tests/config.py
log main-1 modified src/config.py
log main-1 modified tests/config.py
log sub-2  checked  src/config.py
sleep 0.5
{ pkill -P "$WPID"; kill "$WPID"; wait "$WPID"; } 2>/dev/null

# Count only verdict lines (SEAL / ok / ALERT).
grep -E '^(SEAL|ok|ALERT) ' out.txt > verdicts.txt
cat verdicts.txt
got=$(cut -c1-5 verdicts.txt | tr -d ' ' | paste -sd' ' -)
want="SEAL ok ALERT SEAL ok SEAL SEAL ok SEAL SEAL ok"

# Event -> seen delay in ms (includes the cost of reading the clock).
awk -F'event=|seen=' '{ split($2, a, /[:. |]+/); split($3, b, /[:.]/);
  e = ((a[1]*60 + a[2])*60 + a[3])*1000 + a[4]; s = ((b[1]*60 + b[2])*60 + b[3])*1000 + b[4];
  d = s - e; if (d < 0) d += 86400000; if (NR == 1 || d < mn) mn = d; if (d > mx) mx = d; sum += d }
  END { if (NR) printf "event -> seen: %d-%d ms (avg %.1f) over %d events\n", mn, mx, sum/NR, NR }' verdicts.txt

if [ "$got" = "$want" ]; then echo "PASS"; exit 0; else echo "FAIL: got '$got' want '$want'"; exit 1; fi
