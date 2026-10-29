#!/usr/bin/env bash
# tamper-seal: check the log's hash chain.
# Usage: TS_DIR=<log folder> verify.sh
#   exit 0 = chain intact (prints the head: the newest chain value; keep a copy elsewhere
#            to also catch someone rewriting the whole chain or cutting off the end)
#   exit 1 = chain broken (prints the first line where it breaks)
D="${TS_DIR:?set TS_DIR to the log folder}"
exec python3 - "$D/events.log" <<'PY'
import hashlib, sys
path = sys.argv[1]
try:
    data = open(path, "rb").read()
except FileNotFoundError:
    print("no log yet"); sys.exit(0)
prev, started, offset, legacy, chained, last_seq = "genesis", False, 0, 0, 0, "?"
rows = data.split(b"\n")
for n, raw in enumerate(rows, 1):
    if raw == b"" and n == len(rows):
        break                                        # file ends with a newline
    fields = raw.decode("utf-8", "replace").split("\t")
    kv = dict(f.split("=", 1) for f in fields if "=" in f)
    if "chain" in kv:
        if not started and offset:                  # older unchained lines come first
            prev = hashlib.sha256(data[:offset]).hexdigest()
        line = "\t".join(f for f in fields if not f.startswith("chain="))
        want = hashlib.sha256((prev + "\t" + line).encode()).hexdigest()[:16]
        if kv["chain"] != want:
            print("BROKEN at line %d (seq=%s): this line or an earlier one was edited, "
                  "deleted or inserted." % (n, kv.get("seq", "?")))
            sys.exit(1)
        prev, started, chained, last_seq = kv["chain"], True, chained + 1, kv.get("seq", "?")
    elif started:
        print("BROKEN at line %d (seq=%s): a line without a chain value was added after "
              "the chain started (inserted or forged)." % (n, kv.get("seq", "?")))
        sys.exit(1)
    else:
        legacy += 1
    offset += len(raw) + 1
older = " (%d older unchained lines before them)" % legacy if legacy else ""
if chained:
    print("OK: %d chained lines%s, chain intact. Head: %s (seq=%s)" % (chained, older, prev, last_seq))
else:
    print("OK: %d lines, none chained yet" % legacy)
PY
