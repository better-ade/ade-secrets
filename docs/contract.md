# ade-secrets contract (v1)

How a hub's `bin/secret` and `bin/keys` delegate to `ade-secrets`, and what Claude Code's key helper can rely on.
`tests/test_contract.sh` runs the delegation block below as written, so this file and the tested behaviour agree.

## Commands a hub may call

| Call | Where it works | Output | Exit |
|---|---|---|---|
| `ade-secrets set <name> --helper --kind api-key --used-by hub` | the user's own terminal | prompts on the terminal; nothing on stdout | 0 stored, 1 failed |
| `ade-secrets list --names` | the user's own terminal | one name per line, never a value | 0 |
| `ade-secrets forget <name>` | the user's own terminal | asks the user to type the name | 0 forgotten, 1 not |
| `ade-secrets get <name>` (or `helper <name>`) | Claude Code's key helper only | the one value and a newline, nothing else | 0 |

Exit codes for every command: 0 ok, 1 failed (nothing printed on stdout), 2 usage or no store chosen, 3 refused (an
agent context, or `get` outside the key helper), 4 no clipboard (over SSH or without a display), 5 the age store is
locked. Messages go to stderr and never contain a value. Names are `[A-Za-z0-9][A-Za-z0-9._-]{0,63}`.

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

## The key helper: what tells it apart

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
as its parent (directly, or through `/bin/sh`). There is no positive signal, so `ade-secrets` uses the explicit
`get`/`helper` entry point that Claude Code's settings point at and **fails closed** unless all of these hold:

1. none of `CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_PID CLAUDE_CODE_SESSION_ID CLAUDE_CODE_BRIDGE_SESSION_ID
   CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_CODE_EXECPATH CLAUDE_CODE_SSE_PORT` is set (`CLAUDE_CODE_ENTRYPOINT`
   is allowed: the helper inherits it);
2. no terminal on stdin, stdout or stderr;
3. the nearest non-shell ancestor (within four steps) is a claude process;
4. the entry was enabled for the helper by the user, in their own terminal (`set <name> --helper`).

Every other command refuses when any of those variables (including `CLAUDE_CODE_ENTRYPOINT`) is set, when a claude
process is anywhere among its ancestors, or when stdin is not a terminal.

### Residual risk (recorded, not solved)

- **Same user, no boundary.** An agent runs as the user. One determined to read a key can unset the variables, rebuild
  the process tree (`exec /bin/sh -c ...`, a double fork) or allocate a pseudo-terminal, and pass these checks; it can
  also read the age session file while the store is unlocked. These checks stop an agent using the store by accident
  or by instruction; they are not a sandbox. Keep Claude Code's own guards on: `permissions.deny` rules for Bash
  commands that run `ade-secrets` or the hub's `bin/secret`, and the sandbox where it is available.
- **Allow-listing limits the damage:** `get` returns only entries set `--helper`, the keys Claude Code itself is given.
- **Fail closed has a cost:** a claude started from an IDE terminal (which sets `CLAUDECODE`) or from inside another
  Claude Code session inherits the markers, so its key helper is refused. Start it from a plain terminal.
- **The age store and the helper:** `get` does not keep an age session open, so the helper fails once the store locks
  after 5 idle minutes. Use the Keychain or pass for keys the helper serves.
- **Undocumented details can change:** the helper's variables and parentage were observed on one version. If a Claude
  Code release starts passing a marker to the helper, `get` refuses (closed), and this file and the checks are updated.
