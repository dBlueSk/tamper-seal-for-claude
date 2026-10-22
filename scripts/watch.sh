#!/usr/bin/env bash
# tamper-seal watcher: follows the event log and prints one verdict per event.
#   modified -> SEAL  (new trusted fingerprint, no alarm)
#   checked  -> ok    (matches the seal) or ALERT (changed without a log entry)
# Usage: TS_DIR=<log folder> watch.sh
D="${TS_DIR:?set TS_DIR to the log folder}"
touch "$D/events.log"

# Some awk versions buffer pipe input for ~2 s; -W interactive (mawk) avoids that.
if awk -W interactive 'BEGIN{}' >/dev/null 2>&1; then AWK="awk -W interactive"; else AWK="awk"; fi

now_ms() {
  if date -u +%3N 2>/dev/null | grep -qE '^[0-9]{3}$'; then date -u +%T.%3N
  elif command -v gdate >/dev/null 2>&1; then gdate -u +%T.%3N
  else python3 -c 'import datetime as d;print(d.datetime.now(d.timezone.utc).strftime("%H:%M:%S.%f")[:-3])'
  fi
}

# shellcheck disable=SC2016  # awk program is intentionally single-quoted
tail -n0 -F "$D/events.log" 2>/dev/null | $AWK -F '\t' '
{
  delete v
  for (i = 1; i <= NF; i++) { p = index($i, "="); if (p) v[substr($i, 1, p - 1)] = substr($i, p + 1) }
  t = v["target"]; s = v["sha"]; a = v["action"]; ts = substr(v["ts"], 12, 12)
  if (a == "modified") {
    print "SEAL   seq=" v["seq"] " " v["session"] " logged an edit -> trusted sha=" s " | " t " | event=" ts
    trusted[t] = s; by[t] = v["session"]
  } else if ((t in trusted) && trusted[t] != s) {
    print "ALERT  seq=" v["seq"] " " v["session"] " found sha=" s " but last logged edit (" by[t] ") was sha=" trusted[t] " | " t " | event=" ts
  } else if (t in trusted) {
    print "ok     seq=" v["seq"] " " v["session"] " checked, sha=" s " matches seal | " t " | event=" ts
  } else {
    print "ok     seq=" v["seq"] " " v["session"] " checked, sha=" s " (no seal yet) | " t " | event=" ts
  }
  fflush()
}' | while IFS= read -r line; do echo "$line | seen=$(now_ms)"; done
