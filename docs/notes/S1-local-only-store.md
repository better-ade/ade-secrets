# S1 design note: the local-only store

Story: `docs/stories/S1-local-only-store.md`. Risk: high (secrets).

## Shape
- One script, `bin/ade-secrets` (Bash 3.2; python3 only to hash clipboard contents). The store home is
  `ADE_SECRETS_HOME` (default `~/.ade-secrets`, mode 700): `store` (the recorded backend), `meta` (TSV: name, store,
  kind, used-by, created, rotated, helper; never a value), and for age `age/identity.age`, `age/recipient`,
  `age/entries/<name>.age`, `session/identity` while unlocked.
- Backends: `keychain` (`security -i` with the command on stdin, read back after, as the hub's `bin/secret` does),
  `pass` (`insert -m` on stdin), `age` (a generated identity encrypted with the passphrase; `unlock` decrypts it into
  the session file; entries are encrypted to its public key). Values move through pipes and one unexported shell
  variable; they are never an argument, an environment variable, a log line or a message.
- The backend comes from `ADE_SECRETS_STORE`, else the recorded one, else exit 2. A missing tool is an error, never
  a fallback. A different `ADE_SECRETS_STORE` is announced ("switched store"), entries left in other stores are
  reported on every command, and copy/forget point at the store that has an entry instead of reading it there.
- Idle lock: `unlock` starts a reaper that removes the session file after `ADE_SECRETS_IDLE` seconds (at most 300)
  without use; every command also checks the file's age, so a lost reaper still locks.
- Clipboard: macOS through `osascript` (JXA, value on stdin) with `org.nspasteboard.ConcealedType` and
  `TransientType`; Linux through wl-copy, xclip or xsel. Clearing compares a SHA-256 of the clipboard with the copied
  value, so a newer copy is left alone. Over SSH (or without a display) copy exits 4 before reading the value.
- Local only and the key helper: see `docs/contract.md` (what Claude Code's docs say, what was observed, the checks,
  the residual risk).

## Decisions
- `get` has an alias `helper`; both need the entry set `--helper` (allow-list), so the helper path can only return the
  keys Claude Code is meant to get.
- Labels (`--kind`, `--used-by`) are added to `set` so `list` has something to show; they are not secret.
- `help` and `version` work anywhere (they touch no store); every other command but `get` is guarded.

## Tests
- `tests/pty_run.py` runs each command detached (its parent re-parented to init), in a pty or with no terminal, so
  the session running the tests is never an ancestor, and records the whole screen stream for value scans.
- PATH is hermetic (fakes plus an allow-list of system tools): the real Keychain, pass, age and clipboard are never
  reachable from a test. Fakes log argv and the full environment of every call.
