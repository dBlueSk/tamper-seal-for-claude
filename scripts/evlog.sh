#!/usr/bin/env bash
# tamper-seal: append one ID-stamped line to the shared event log.
# Usage: TS_DIR=<log folder> evlog.sh SESSION_ID ACTION FILE
#   ACTION: modified (a logged edit, sets the seal) | checked (verify against the seal)
# Log format: tab-separated key=value fields, target last (full path).
# Each line carries chain=<sha256 of (previous chain, this line)>; scripts/verify.sh checks it.
set -euo pipefail

D="${TS_DIR:?set TS_DIR to the log folder}"
[ $# -eq 3 ] || { echo "usage: evlog.sh SESSION_ID modified|checked FILE" >&2; exit 2; }
sid="$1"; act="$2"; tgt="$3"

case "$act" in modified|checked) ;; *) echo "evlog: ACTION must be modified or checked" >&2; exit 2;; esac
case "$sid$tgt" in *$'\t'*|*$'\n'*) echo "evlog: tabs/newlines not allowed in session or path" >&2; exit 2;; esac
case "$sid" in *=*|"") echo "evlog: SESSION_ID must be non-empty and contain no '='" >&2; exit 2;; esac

# Absolute path, so src/config.py and tests/config.py stay separate.
dir=$(cd "$(dirname "$tgt")" 2>/dev/null && pwd -P) || dir="$(dirname "$tgt")"
abs="$dir/$(basename "$tgt")"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi
}
sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
}
now_ms() {  # UTC time with milliseconds; GNU date, gdate (macOS coreutils) or python3
  if date -u +%3N 2>/dev/null | grep -qE '^[0-9]{3}$'; then date -u +%FT%T.%3NZ
  elif command -v gdate >/dev/null 2>&1; then gdate -u +%FT%T.%3NZ
  else python3 -c 'import datetime as d;print(d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]+"Z")'
  fi
}

sha=$(sha256 "$abs" 2>/dev/null | cut -c1-12) || true
[ -z "${sha:-}" ] && sha=none

command -v flock >/dev/null 2>&1 || { echo "evlog: flock not found (macOS: brew install flock)" >&2; exit 1; }
(
  flock 9
  seq=0; [ -s "$D/events.seq" ] && read -r seq < "$D/events.seq"; seq=$(( seq + 1 ))
  echo "$seq" > "$D/events.seq"
  # Hash chain: link this line to the previous one. An older log without chains is
  # linked through the sha256 of everything written before this line.
  # The newest chain value is cached in events.head (written under the same lock).
  if [ ! -s "$D/events.log" ]; then prev=genesis
  elif [ -s "$D/events.head" ]; then read -r prev < "$D/events.head"
  else
    prev=$(tail -n 1 "$D/events.log" | tr '\t' '\n' | sed -n 's/^chain=//p' | head -n 1)
    [ -n "$prev" ] || prev=$(sha256_stdin < "$D/events.log" | cut -c1-64)
  fi
  ts=$(now_ms)
  printf -v line 'seq=%s\tts=%s\tsession=%s\taction=%s\tsha=%s\ttarget=%s' "$seq" "$ts" "$sid" "$act" "$sha" "$abs"
  chain=$(printf '%s\t%s' "$prev" "$line" | sha256_stdin); chain=${chain:0:16}
  printf 'seq=%s\tts=%s\tsession=%s\taction=%s\tsha=%s\tchain=%s\ttarget=%s\n' \
    "$seq" "$ts" "$sid" "$act" "$sha" "$chain" "$abs" >> "$D/events.log"
  echo "$chain" > "$D/events.head"
) 9>"$D/events.lock"
