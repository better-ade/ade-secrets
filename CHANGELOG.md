# Changelog

## Unreleased

- S3 (contract v2): scoped names, `<scope>.<key>` (a scope is up to 40 of a-z, 0-9 and `-`); the stores keep the full
  name flat. `list` and the vault show a SCOPE column, `list --scope S` and `vault --scope S` keep one scope; v1
  entries show `-` and are left as they are.
- `set` asks `replace <name> (rotated <age> ago)? [y/N]` before it replaces an entry (and before the age passphrase);
  anything but `y` keeps it (exit 1). `--plain` means `--no-helper`.
- `has <name>`: exit 0 present, 1 absent, nothing printed, in every context (start-up check only); it reads meta and
  the item's record (Keychain attributes, the pass file, the age file), never a value.
- `list --due [--scope S]`: names past `ADE_SECRETS_ROTATE_DAYS` (default 90), one per line.
- The version is a line in the script (`ADE_SECRETS_VERSION`), printed by `--version` without reading `VERSION`.
- `list`, `status` and the vault show fields from `meta` with every control, direction-changing or invisible
  character replaced by `?`; the vault no longer evaluates a rotation time from `meta` as shell arithmetic.

## 0.3.0

- S2: `ade-secrets vault`, the full-screen terminal vault: list and search (never values), add by hidden prompt,
  clipboard or generator, copy with enter, rotate behind the entry's live test (the old value is kept when it fails),
  notes, typed-name delete, rotation reminders (default 90 days), lock/unlock, and an opt-in, confirmed 10 s reveal.
- Prompts go to the terminal itself; the hidden prompt turns echo off before it shows.
- Review fixes: the age identity stays in the vault's memory (idle lock at most 300 s), the live-test command is shown
  and confirmed before it runs, notes and commands are drawn without control characters, private runtime folders, the
  clipboard cleared on every exit of add and rotate, ^Z ignored during a reveal, the store line kept on screen; the
  tests use the pty harness (`--own-pgrp` and a `run` step added).

## 0.2.0

- S1: `bin/ade-secrets`, the local-only store: Keychain, pass or age backends chosen explicitly; `list`, `set`
  (hidden prompt or clipboard), `copy` (concealed, cleared after N s if unchanged), `forget`, `lock`, `unlock`,
  `status`, and `get`/`helper` for Claude Code's key helper only. Refuses inside an agent context.
- `docs/contract.md`: the hub delegation block for `bin/secret`/`bin/keys` and the key-helper signal and its risks.
- CI runs the verification command on macOS and Ubuntu.
- Review fixes: helper entries documented as readable by Claude Code; Keychain entries not set `--helper` trust no
  application (`-T ""`); the age store keeps no session; private store folders; case-only name clashes refused;
  `bash -p` and `/bin/ps`; the clipboard cleared on every `set --clipboard` exit, `copy` default 10 s; the store is
  recorded once and switched only by `ade-secrets store`; `docs/claude-settings.json`; Residual risk and Owner check.

## 0.1.0

- Stories S1 (local-only store) and S2 (terminal vault).
