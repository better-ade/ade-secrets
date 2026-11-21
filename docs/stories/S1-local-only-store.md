# S1: the local-only store, `ade-secrets` core

Status: Ready for development (2026-11-21); review fix round 2026-11-22 (AC4 reworded: the key-helper checks are an
accident guard, helper entries are readable by Claude Code; AC5-7 follow the fixes). Risk: high. Owner's intent (2026-11-21): keys in a local store that runs
outside any Claude Code session; the clipboard moves a key from the store to where it is needed.
Verification command: `bash tests/run.sh` (macOS bash 3.2 and Linux bash 5 in CI).

## Goal
A single script `ade-secrets` (Bash 3.2 + python3 for small helpers) with backends: macOS Keychain (`security`, values on
stdin with `-i`), Linux `pass`, or a file store encrypted with `age` (the passphrase is asked on each `set` and `copy`;
no session, so nothing plaintext on disk). The backend is chosen explicitly (`ADE_SECRETS_STORE` for the first entry,
then recorded; `ade-secrets store <name>` is the only way to change it), never switched silently.
```
ade-secrets list                       names, kinds, used-by, age; never values
ade-secrets set <name> [--clipboard]   hidden prompt, or from the clipboard (then cleared)
ade-secrets copy <name> [--for N]      to the clipboard, concealed on macOS, cleared after N s (default 10) if unchanged
ade-secrets forget <name>              after typing the name
ade-secrets store [<name>]             show the recorded store, or switch it explicitly
ade-secrets get <name>                 for Claude Code's key helper (apiKeyHelper), entries set --helper only: the one value
ade-secrets lock|unlock|status
```
**Local only:** every command except `get` refuses (exit 3, "run this in your own terminal") when it detects an agent
context: `CLAUDECODE` or other Claude Code session variables in the environment, a `claude` process among its
ancestors, or no TTY. `get` is allowed only when invoked as Claude Code's key helper (the builder verifies the exact
signal Claude Code gives a key-helper process against its docs, records it in docs/contract.md, and fails closed when
unsure). Claude Code documents no such signal, so the context checks are an accident guard only: **helper entries
(`--helper`) are readable by Claude Code and anything it runs**, and `get` never returns any other entry. Direct reads
of the stores are limited by the stores themselves (Keychain trusted-application lists, no age session) and by the
Claude Code rules in `docs/claude-settings.json`; what remains is listed in docs/contract.md. Values never reach argv,
the environment, a log, a file outside the store, or the screen (except an opt-in timed reveal in S2).

## Acceptance criteria (`tests/`, fakes for security/pass/age/clipboard, a fake claude ancestor)
| AC | Criterion |
|---|---|
| 1 | Each backend round-trips set/copy/forget with values on stdin only (fakes record argv and env) |
| 2 | `list` never shows a value (output scan) |
| 3 | Every command except `get` refuses with `CLAUDECODE=1`, with a claude ancestor, and without a TTY |
| 4 | `get` prints only entries set `--helper`, only in a key-helper-like context (no tool markers, no terminal, claude the nearest non-shell parent): an accident guard, documented as such; any other entry is refused in every context |
| 5 | `copy` clears after N s (default 10) only if unchanged; macOS concealed marker set; over SSH without a clipboard it refuses; a value taken from the clipboard is cleared on every exit path |
| 6 | The age store is encrypted at rest and keeps no session (no plaintext identity on disk; the recipient comes from the identity); copy and set refuse without the right passphrase |
| 7 | The backend never switches silently: recorded once, changed only by `ade-secrets store <name>`; a store with entries left behind after a switch is reported |
| 8 | A hub can delegate: `bin/secret`/`bin/keys` call `ade-secrets` when installed (contract in docs/contract.md) |
| 9 | Hardening (review): the store folders are refused when a symlink, not the user's or not mode 700; a name equal to an existing one ignoring case is refused; the script runs as `bash -p` and its guards call `/bin/ps` by path; Keychain entries not set `--helper` trust no application (`-T ""`) (`tests/test_hardening.sh`, `tests/test_backends.sh`) |
| 10 | The docs say what remains (review): `docs/claude-settings.json` ships the deny and ask rules; docs/contract.md has "Residual risk" and "Owner check" (`tests/test_settings.sh`) |
