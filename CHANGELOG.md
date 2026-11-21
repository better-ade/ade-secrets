# Changelog

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
