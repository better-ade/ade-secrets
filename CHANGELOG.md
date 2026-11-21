# Changelog

## 0.2.0

- S1: `bin/ade-secrets`, the local-only store: Keychain, pass or age backends chosen explicitly; `list`, `set`
  (hidden prompt or clipboard), `copy` (concealed, cleared after N s if unchanged), `forget`, `lock`, `unlock`,
  `status`, and `get`/`helper` for Claude Code's key helper only. Refuses inside an agent context.
- `docs/contract.md`: the hub delegation block for `bin/secret`/`bin/keys` and the key-helper signal and its risks.
- CI runs the verification command on macOS and Ubuntu.

## 0.1.0

- Stories S1 (local-only store) and S2 (terminal vault).
