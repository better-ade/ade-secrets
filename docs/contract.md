# ade-secrets contract (v1)

How a hub's `bin/secret` and `bin/keys` delegate to `ade-secrets`, and what Claude Code's key helper can rely on.
`tests/test_contract.sh` runs the delegation block below as written, so this file and the tested behaviour agree.

## Commands a hub may call

| Call | Where it works | Output | Exit |
|---|---|---|---|
| `ade-secrets set <name> --helper --kind api-key --used-by hub` | the user's own terminal | prompts on the terminal; nothing on stdout | 0 stored, 1 failed |
| `ade-secrets list --names` | the user's own terminal | one name per line, never a value | 0 |
| `ade-secrets forget <name>` | the user's own terminal | asks the user to type the name | 0 forgotten, 1 not |
| `ade-secrets get <name>` (or `helper <name>`) | Claude Code's key helper, for entries set `--helper` | the one value and a newline, nothing else | 0 |

Exit codes for every command: 0 ok, 1 failed (nothing printed on stdout), 2 usage, no store chosen, or an
`ADE_SECRETS_STORE` that differs from the recorded store, 3 refused (an agent context, or an entry not set
`--helper`), 4 no clipboard (over SSH or without a display), 5 the age store is locked (a wrong passphrase, or `get`,
which it cannot serve). Messages go to stderr and never contain a value. Names are `[A-Za-z0-9][A-Za-z0-9._-]{0,63}`;
a name that differs from an existing entry only in case is refused (exit 2), since pass and age keep a file per name
and macOS paths ignore case.

**Helper entries are readable by Claude Code and anything it runs.** An entry set `--helper` is the key Claude Code is
given; its Bash tool, hooks and MCP servers can read it too (`env -u CLAUDECODE ... ade-secrets get <name>` passes the
checks below). Entries not set `--helper` are never returned by `get`, whatever the context.

The store: the first `set` (or `unlock` for age) records the store `ADE_SECRETS_STORE` names, once. After that only
`ade-secrets store <name>` changes it (announced: `switched store: A -> B; nothing was moved`, with the entries left in
A); an `ADE_SECRETS_STORE` that differs from the record is refused, not followed. `ade-secrets store` shows the record.

A hub never reads a value outside the key helper. A presence check uses `list --names`, which refuses (exit 3) inside
an agent session, like every command but `get`: the hub reports "run this in your own terminal", never "missing".

## The delegation block (bin/secret)

A hub's `bin/secret` puts this right after its `set -u` line. It delegates when `ade-secrets` is on `PATH`, unless
`HUB_SECRETS=builtin` keeps the hub's own Keychain code. `bin/keys` needs no block of its own: it reaches the store
through `bin/secret`; only its `security`-command check is skipped when `ade-secrets` is installed.

```bash
# >>> ade-secrets delegation (docs/contract.md v1 in better-ade/ade-secrets)
if [ "${HUB_SECRETS:-}" != builtin ] && command -v ade-secrets >/dev/null 2>&1; then
  case "${1:-}" in
    --set) [ -n "${2:-}" ] || exit 2; exec ade-secrets set "$2" --helper --kind api-key --used-by hub ;;
    --has) [ -n "${2:-}" ] || exit 2; names="$(ade-secrets list --names)" || exit $?
      printf '%s\n' "$names" | grep -qxF -- "$2"; exit $? ;;
    --forget) [ -n "${2:-}" ] || exit 2; exec ade-secrets forget "$2" ;;
    --list) exec ade-secrets list --names ;;
    ""|-*) ;;
    *) exec ade-secrets get "$1" ;;
  esac
fi
# <<< ade-secrets delegation
```

The hub's apiKeyHelper line stays as it is (`... /path/to/hub/bin/secret <name>`): Claude Code runs it, `bin/secret`
execs `ade-secrets get <name>`, and the value reaches Claude Code on stdout. Moving a key from the hub's own Keychain
service is a re-entry in the user's terminal (`bin/keys set <tool>`); nothing is copied across automatically.

## The key helper: what it can and cannot tell apart

Claude Code's docs (code.claude.com, settings reference, `apiKeyHelper`; checked 2026-11-21) say the helper is "a shell
command line" that Claude Code "runs through the system shell, `/bin/sh` on macOS and Linux", and sends its stdout as
the credential. **They document no variable, argument or descriptor that marks a key-helper process.** What they do
document is where Claude Code's own markers are set (env-vars reference):

- `CLAUDECODE=1`: "subprocesses Claude Code spawns (Bash and PowerShell tools, tmux sessions, hook commands, status line
  commands, stdio MCP server subprocesses)", and IDE integrated terminals. The key helper is not in the list.
- `CLAUDE_CODE_CHILD_SESSION=1`: "subprocesses Claude Code spawns via the Bash, PowerShell, and Monitor tools, hook
  commands, and status line commands", set by Claude Code only.
- `CLAUDE_PID`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_BRIDGE_SESSION_ID`: Bash tool and hook subprocesses (session ID
  also MCP servers). `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`: hooks, plugins and MCP servers.

Checked against Claude Code 2.1.330 on macOS (a helper that recorded variable names only, with a throwaway key): the
helper had `CLAUDE_CODE_ENTRYPOINT` but none of the markers above, no terminal on stdin, stdout or stderr, and claude
as its parent (directly, or through `/bin/sh`). There is no positive signal, so these checks are an **accident guard,
not a boundary**: anything Claude Code runs can unset the variables and run through `/bin/sh`, and then reads helper
entries. What keeps every other key out is item 4, the allow-list. `get` refuses unless all of these hold:

1. none of `CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_PID CLAUDE_CODE_SESSION_ID CLAUDE_CODE_BRIDGE_SESSION_ID
   CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_CODE_EXECPATH CLAUDE_CODE_SSE_PORT` is set (`CLAUDE_CODE_ENTRYPOINT`
   is allowed: the helper inherits it);
2. no terminal on stdin, stdout or stderr;
3. the nearest non-shell ancestor (within four steps) is a claude process;
4. the entry was enabled for the helper by the user, in their own terminal (`set <name> --helper`).

Every other command refuses when any of those variables (including `CLAUDE_CODE_ENTRYPOINT`) is set, when a claude
process is anywhere among its ancestors, or when stdin is not a terminal. The guards read the process table with
`/bin/ps` by path, and the script runs as `bash -p` (no exported functions, `BASH_ENV` or `SHELLOPTS` from the caller).

## Reads outside the tool

The checks above only cover `ade-secrets` itself. Each store also limits a direct read:

- **Keychain.** An entry not set `--helper` is created with an empty trusted-application list (`-T ""`), so macOS
  asks the user, in its own dialog, on every read of its value, by `ade-secrets copy` or by anyone running `security`.
  A helper entry trusts `/usr/bin/security`, so the key helper reads it without a dialog. Changing an entry's helper
  flag deletes and re-adds its item (a trusted list is set when an item is created). Because `security -i` hides a
  failed command and reading the value back would ask again, a write is checked through the item's `mdat` timestamp
  (a write in the same second waits for the next one). Observed on a throwaway keychain by the S1 builder: an update
  of a `-T ""` item raises the allow dialog too; Deny there is reported as a failed `set`.
- **age.** No session file at all: the identity stays encrypted with the passphrase, `set` and `copy` ask for the
  passphrase each time, decrypt the identity into the process's memory and hand it to age on a pipe. Nothing
  plaintext is written to disk. The recipient is derived from the identity (`age-keygen -y`), never read from a file.
  `unlock` only creates the store (or checks the passphrase); `lock` has nothing to close. The store folder and its
  `age` and `entries` folders are refused when a symlink, not the user's, or not mode 700 (never repaired silently).
- **pass.** Values are decrypted by gpg, and gpg-agent caches the passphrase: keep that cache short, for example
  `default-cache-ttl 60` and `max-cache-ttl 300` in `~/.gnupg/gpg-agent.conf`, then `gpgconf --reload gpg-agent`.

### Claude Code settings: docs/claude-settings.json

`docs/claude-settings.json` holds the permission rules to merge into `~/.claude/settings.json` (every project) or a
project's `.claude/settings.json`: `permissions.deny` for `Read(~/.ade-secrets/**)`, `Bash(security
find-generic-password*)`, `Bash(security dump-keychain*)`, `Bash(pass show*)` and `Bash(pbpaste*)`, and
`permissions.ask` for `Bash(ade-secrets *)`, so Claude Code asks before any command that runs `ade-secrets`. They are
pattern matches on the plain command: they stop accidents, not an agent that writes the command another way.

## Residual risk

Every route that remains, plainly. ade-secrets runs as the user, like the agent; nothing here is a sandbox.

- **Same user, no boundary.** An agent can unset the variables, rebuild the process tree (`exec /bin/sh -c ...`, a
  double fork) or allocate a pseudo-terminal, and pass every check. The checks stop use by accident or by instruction.
- **Helper entries** are readable by Claude Code and anything it runs, without a dialog. Mark `--helper` only the keys
  Claude Code itself is given.
- **The Keychain dialog** is the user's decision. Allow on a dialog an agent's command raised gives that one read away;
  **Always Allow** adds the asking program to the item's trusted list for good. Read which program the dialog names.
- **pass:** while gpg-agent holds the passphrase, any process of the user decrypts entries (`pass show`, or `gpg -d`
  on `~/.password-store/ade-secrets/*.gpg`) with no prompt. Only the cache time limits this.
- **age:** the passphrase is typed into a terminal; a program that controls that terminal, or a fake `age` earlier on
  `PATH`, sees it.
- **PATH:** `security`, `pass`, `age`, `age-keygen` and the clipboard tools are found through `PATH` (only the guards'
  `ps` is called by path). A `PATH` changed by an agent (a shell startup file, a folder put first) can put a fake in
  front that records values when the user runs `ade-secrets`.
- **The clipboard:** while a copied key is on it (10 s by default), any process of the user reads it (`pbpaste`,
  `osascript`, `wl-paste`, `xclip`, `xsel`). The concealed and transient markers only keep it out of clipboard managers
  that honour them. With `set --clipboard`, the key sits there until ade-secrets clears it (on every exit path).
- **Permission rules** match the plain commands only: `sh -c`, a script file, `python3 -c` with `subprocess`, or
  `cat` instead of the Read tool pass them. Use Claude Code's sandbox where it is available.
- **Memory:** a value lives in the ade-secrets process (a shell variable) for the length of one command; a debugger
  running as the user, where the system allows one to attach, can read it.
- **Fail closed has a cost:** a claude started from an IDE terminal (which sets `CLAUDECODE`) or from inside another
  Claude Code session inherits the markers, so its key helper is refused. Start it from a plain terminal.
- **The age store cannot serve the key helper** (`get` exits 5): it asks for the passphrase on every read. Use the
  Keychain or pass for keys the helper serves.
- **Undocumented details can change:** the helper's variables and parentage were observed on one version. If a Claude
  Code release starts passing a marker to the helper, `get` refuses (closed), and this file and the checks are updated.

## Owner check

What only a real Keychain can confirm. The tests use fakes only; run these by hand, in your own terminal, with a
throwaway value (not a real key), and answer each dialog yourself.

1. `ade-secrets set owner-check-closed` (type `throwaway-1`), then
   `security find-generic-password -s ade-secrets -a owner-check-closed -w`: the macOS allow dialog shows. Press
   **Deny**: nothing is printed and the exit is not 0. (A read of a non-helper entry shows the dialog.)
2. `ade-secrets copy owner-check-closed`: the dialog shows; press **Allow** (not Always Allow): the value is copied.
3. `ade-secrets set owner-check-closed` again (type `throwaway-2`): the dialog shows for the update. Press **Deny**:
   `set` says it could not store and exits 1. Run it again and press **Allow**: it says stored.
4. `ade-secrets set owner-check-helper --helper` (type `throwaway-3`), then
   `security find-generic-password -s ade-secrets -a owner-check-helper -w`: it prints `throwaway-3` with no dialog.
5. `security find-generic-password -s ade-secrets -a owner-check-helper | grep mdat`: one line of the form
   `"mdat"<timedate>=0x... "YYYYMMDDhhmmssZ\000"` (the format the write check reads).
6. `ade-secrets set owner-check-closed --helper` (type `throwaway-4`): the item is deleted and re-added (note whether
   the delete shows a dialog); then step 4's `security` command for `owner-check-closed` prints with no dialog.
7. `ade-secrets forget owner-check-closed` and `ade-secrets forget owner-check-helper`: both are gone
   (`security find-generic-password -s ade-secrets -a owner-check-helper` exits 44). Note any dialog.
