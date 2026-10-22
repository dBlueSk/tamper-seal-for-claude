#!/usr/bin/env bash
# tamper-seal: append one ID-stamped line to the shared event log.
# Usage: TS_DIR=<log folder> evlog.sh SESSION_ID ACTION FILE
#   ACTION: modified (a logged edit, sets the seal) | checked (verify against the seal)
# Log format: tab-separated key=value fields, target last (full path).
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
  seq=$(( $(cat "$D/events.seq" 2>/dev/null || echo 0) + 1 ))
  echo "$seq" > "$D/events.seq"
  printf 'seq=%s\tts=%s\tsession=%s\taction=%s\tsha=%s\ttarget=%s\n' \
    "$seq" "$(now_ms)" "$sid" "$act" "$sha" "$abs" >> "$D/events.log"
) 9>"$D/events.lock"
