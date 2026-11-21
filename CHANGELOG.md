# Changelog

## 0.3.0

- S2: `ade-secrets vault`, the full-screen terminal vault: list and search (never values), add by hidden prompt,
  clipboard or generator, copy with enter, rotate behind the entry's live test (the old value is kept when it fails),
  notes, typed-name delete, rotation reminders (default 90 days), lock/unlock, and an opt-in, confirmed 10 s reveal.
- Prompts go to the terminal itself; the hidden prompt turns echo off before it shows.

## 0.2.0

- S1: `bin/ade-secrets`, the local-only store: Keychain, pass or age backends chosen explicitly; `list`, `set`
  (hidden prompt or clipboard), `copy` (concealed, cleared after N s if unchanged), `forget`, `lock`, `unlock`,
  `status`, and `get`/`helper` for Claude Code's key helper only. Refuses inside an agent context.
- `docs/contract.md`: the hub delegation block for `bin/secret`/`bin/keys` and the key-helper signal and its risks.
- CI runs the verification command on macOS and Ubuntu.

## 0.1.0

- Stories S1 (local-only store) and S2 (terminal vault).
