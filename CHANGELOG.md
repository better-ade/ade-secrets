# Changelog

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
