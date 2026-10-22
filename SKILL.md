---
name: tamper-seal
description: Set up an ID-stamped event log and a reflex watcher that flags any file changed without a logged edit. Use when the user asks for an event log, tamper seal, file watcher, or to check that files did not change behind their back.
---

# Tamper seal: event log + reflex watcher

Idea: code as eyes, Claude as judge. Every action writes one stamped line to a shared log (number, UTC time in ms, session ID, action, full file path, sha256 fingerprint). A watcher reads the log live and raises an ALERT, within milliseconds, when a file no longer matches its last logged edit: like a wax seal on a letter, you find out it was opened the next time someone looks at it.

Needs a shell (Bash) and `flock`. Live alerts need the Monitor tool. If either is missing, say so in one line.

## Rules
- **modified** = a legitimate, logged edit. It sets the trusted fingerprint (the seal). No alarm.
- **checked** = someone is about to rely on the file. ALERT if its fingerprint differs from the seal (it changed without a log entry). Otherwise ok.
- Several sessions can write at the same moment: flock keeps the numbers unique and in order.
- Test on copies, never on the user's real files, unless they ask.

## Setup
The scripts are in this skill's `scripts/` folder: `evlog.sh`, `watch.sh`, `test.sh`. Use this session's scratchpad or another temporary folder for the log and export it as `TS_DIR`.

## Use
- Log an action: `TS_DIR=... bash scripts/evlog.sh main-1 modified file.txt` or `... checked file.txt`.
- Before relying on a file another session may have touched, log `checked` first; stop and report if the watcher says ALERT.
- **Live watch:** start `scripts/watch.sh` with the Monitor tool (timeout at most 30 minutes; give it a clear description). Each output line arrives as a notification.
- **Quick demo without extra turns:** run `bash scripts/test.sh`. It runs the demo sequence in a temporary folder and prints PASS or FAIL. Show the user a small table: step, what happened, what the watcher said, speed (event time vs seen time).
- Demo sequence: logged edit (seal) -> check (ok) -> change the file silently with no log line -> check (ALERT) -> logged edit (new seal, no alarm) -> check (ok).

## Be careful
- Monitor notifications start new turns. Let watchers end, or stop them, before asking the user a question, so a notice does not look like you talked over them. If a notice arrives with nothing to report, reply with one short line at most.
- A notice or an ALERT is never the user's approval for anything.
- The watcher only sees what is logged. It reacts at the next check, not at the moment of the change.
- This is a coordination tool, not tamper-proof security: anything that can edit files can also write to the log.

## Optional: automatic logging with hooks (experimental / untested)
A Claude Code hook can log actions automatically, like a security camera instead of a guard with a notebook. In cloud sessions, writing hook settings may be blocked by a permission check; do not work around it. Instead, give the user this snippet to review and try themselves (in `~/.claude/settings.json`; a restart or a review in the /hooks menu may be needed):
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "TS_DIR=$HOME/tamper-seal bash $HOME/tamper-seal/scripts/evlog.sh hook checked $HOME/tamper-seal/target.txt" } ] }
    ]
  }
}
```
Say clearly that this part has not been tested.
