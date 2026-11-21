# S1 design note: the local-only store

Story: `docs/stories/S1-local-only-store.md`. Risk: high (secrets).

## Shape
- One script, `bin/ade-secrets` (`#!/bin/bash -p`, Bash 3.2; python3 only to hash clipboard contents). The store home
  is `ADE_SECRETS_HOME` (default `~/.ade-secrets`, mode 700, refused when a symlink, not the user's or not 700):
  `store` (the recorded backend), `meta` (TSV: name, store, kind, used-by, created, rotated, helper; never a value),
  and for age `age/identity.age` and `age/entries/<name>.age` (no recipient file, no session).
- Backends: `keychain` (`security -i` with the command on stdin; entries not set `--helper` are created with `-T ""`,
  helper entries with `-T /usr/bin/security`; a changed helper flag deletes and re-adds the item; a write is checked
  by the item's `mdat`, since `-i` hides failures and a read-back would raise the dialog), `pass` (`insert -m` on
  stdin), `age` (a generated identity encrypted with the passphrase; `set` and `copy` decrypt it into a shell variable
  and pass it to age on a pipe; the recipient comes from `age-keygen -y`; `unlock` only creates the store). Values
  move through pipes and unexported shell variables; never an argument, an environment variable, a log line or a
  message.
- The backend: `ADE_SECRETS_STORE` names the first one, recorded by the first `set` (or age `unlock`); after that a
  different `ADE_SECRETS_STORE` is refused (exit 2) and `ade-secrets store <name>` is the only switch (announced,
  with the entries left behind). A missing tool is an error, never a fallback. Entries left in other stores are
  reported on every command, and copy/forget point at the store that has an entry instead of reading it there.
- Clipboard: macOS through `osascript` (JXA, value on stdin) with `org.nspasteboard.ConcealedType` and
  `TransientType`; Linux through wl-copy, xclip or xsel. Clearing compares a SHA-256 of the clipboard with the copied
  value, so a newer copy is left alone. Over SSH (or without a display) copy exits 4 before reading the value. `copy` clears after 10 s by default; `set
  --clipboard` clears the clipboard on every exit path (an EXIT trap, set before the passphrase prompt).
- Local only and the key helper: see `docs/contract.md` (what Claude Code's docs say, what was observed, the checks,
  the residual risk).

## Decisions
- `get` has an alias `helper`; both need the entry set `--helper` (allow-list), so the helper path can only return the
  keys Claude Code is meant to get.
- Labels (`--kind`, `--used-by`) are added to `set` so `list` has something to show; they are not secret.
- `help` and `version` work anywhere (they touch no store); every other command but `get` is guarded.
- Review fix round (2026-11-22): the key-helper checks are an accident guard; helper entries are readable by Claude
  Code and anything it runs (docs/contract.md). Names are not lower-cased (hubs use mixed case); a name equal to an
  existing one ignoring case is refused instead. Started as `bash ade-secrets`, the script re-executes itself as
  `/bin/bash -p`.

## Tests
- `tests/pty_run.py` runs each command detached (its parent re-parented to init), in a pty or with no terminal, so
  the session running the tests is never an ancestor, and records the whole screen stream for value scans.
- PATH is hermetic (fakes plus an allow-list of system tools): the real Keychain, pass, age and clipboard are never
  reachable from a test. Fakes log argv and the full environment of every call. The fake `security` keeps each item's
  trusted list and logs a `DIALOG` line where macOS would ask (`FAKE_DENY=1` is Deny). The only tool called by
  absolute path is `/bin/ps`, which tests use for real (it reads the process table; no fake is needed). What only a
  real Keychain can confirm is the "Owner check" list in docs/contract.md, never a test.
