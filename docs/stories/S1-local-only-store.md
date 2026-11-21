# S1: the local-only store, `ade-secrets` core

Status: Ready for development (2026-11-21). Risk: high. Owner's intent (2026-11-21): keys in a local store that runs
outside any Claude Code session; the clipboard moves a key from the store to where it is needed.
Verification command: `bash tests/run.sh` (macOS bash 3.2 and Linux bash 5 in CI).

## Goal
A single script `ade-secrets` (Bash 3.2 + python3 for small helpers) with backends: macOS Keychain (`security`, values on
stdin with `-i`), Linux `pass`, or a file store encrypted with `age` (passphrase, session unlock, auto-lock after 5 idle
minutes). The backend is chosen explicitly (`ADE_SECRETS_STORE`), never switched silently.
```
ade-secrets list                       names, kinds, used-by, age; never values
ade-secrets set <name> [--clipboard]   hidden prompt, or from the clipboard (then cleared)
ade-secrets copy <name> [--for N]      to the clipboard, concealed on macOS, cleared after N s (default 20) if unchanged
ade-secrets forget <name>              after typing the name
ade-secrets get <name>                 ONLY for Claude Code's key helper (apiKeyHelper): prints the one value, nothing else
ade-secrets lock|unlock|status
```
**Local only:** every command except `get` refuses (exit 3, "run this in your own terminal") when it detects an agent
context: `CLAUDECODE` or other Claude Code session variables in the environment, a `claude` process among its
ancestors, or no TTY. `get` is allowed only when invoked as Claude Code's key helper (the builder verifies the exact
signal Claude Code gives a key-helper process against its docs, records it in docs/contract.md, and fails closed when
unsure); it refuses when called from a Bash tool context. Values never reach argv, the environment, a log, a file
outside the store, or the screen (except an opt-in timed reveal in S2).

## Acceptance criteria (`tests/`, fakes for security/pass/age/clipboard, a fake claude ancestor)
| AC | Criterion |
|---|---|
| 1 | Each backend round-trips set/copy/forget with values on stdin only (fakes record argv and env) |
| 2 | `list` never shows a value (output scan) |
| 3 | Every command except `get` refuses with `CLAUDECODE=1`, with a claude ancestor, and without a TTY |
| 4 | `get` prints the value only in the verified key-helper context and refuses from a Bash-tool-like context |
| 5 | `copy` clears after N s only if unchanged; macOS concealed marker set; over SSH without a clipboard it refuses |
| 6 | The age store is encrypted at rest, locks after idle, refuses copy while locked |
| 7 | The backend never switches silently; a store with entries left behind after a switch is reported |
| 8 | A hub can delegate: `bin/secret`/`bin/keys` call `ade-secrets` when installed (contract in docs/contract.md) |
