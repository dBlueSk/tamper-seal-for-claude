#!/usr/bin/env bash
# tamper-seal guard for Claude Code (PreToolUse hook on Edit/Write/MultiEdit/NotebookEdit).
# Before Claude edits a file, compare it with its last logged edit (the seal).
#   unchanged, new, or never logged   -> allow (silent)
#   changed without a log entry       -> block this edit ONCE and tell Claude to re-read;
#                                        the retry of the same session goes through.
# Any internal error allows the edit: the guard must never get in the way by accident.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
HERE="$HOME/.claude/tamper-seal"
export TS_DIR="${TS_DIR:-$HERE/log}"
export TS_HERE="$HERE"
exec python3 -c '
import hashlib, json, os, subprocess, sys
try:
    d = json.load(sys.stdin)
    sid = (d.get("session_id") or "unknown")[:8]
    ti = d.get("tool_input") or {}
    p = ti.get("file_path") or ti.get("notebook_path") or ""
    if not p or not os.path.isfile(p):
        sys.exit(0)                                   # new file: nothing to protect
    p = os.path.join(os.path.realpath(os.path.dirname(os.path.abspath(p))), os.path.basename(p))
    log = os.path.join(os.environ["TS_DIR"], "events.log")
    seal = None                                       # last logged edit of this file
    if os.path.exists(log):
        for line in open(log, encoding="utf-8", errors="replace"):
            f = dict(kv.split("=", 1) for kv in line.rstrip("\n").split("\t") if "=" in kv)
            if f.get("target") == p and f.get("action") == "modified":
                seal = f
    if seal is None:
        sys.exit(0)                                   # never sealed: nothing to compare
    now = hashlib.sha256(open(p, "rb").read()).hexdigest()[:12]
    if now == seal.get("sha"):
        sys.exit(0)                                   # matches the seal
    ackdir = os.path.join(os.environ["TS_DIR"], "acks")
    os.makedirs(ackdir, exist_ok=True)
    ack = os.path.join(ackdir, sid + "-" + hashlib.sha256(p.encode()).hexdigest()[:16])
    if os.path.exists(ack) and open(ack).read().strip() == now:
        sys.exit(0)                                   # this session was already warned about this version
    open(ack, "w").write(now)
    subprocess.run(["bash", os.path.join(os.environ["TS_HERE"], "scripts", "evlog.sh"),
                    "guard-" + sid, "checked", p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    when = (seal.get("ts") or "")[11:19]
    sys.stderr.write(
        "tamper-seal: %s changed after its last logged edit (by %s at %s UTC), and that change "
        "was not logged. Read the file again to see its current content before editing, so you do "
        "not overwrite someone else'"'"'s work. This edit was blocked once; your retry will go through.\n"
        % (p, seal.get("session", "?"), when))
    sys.exit(2)                                       # exit 2 = block the tool call, show stderr to Claude
except SystemExit:
    raise
except Exception:
    sys.exit(0)
'
