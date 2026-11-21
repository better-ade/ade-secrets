#!/bin/bash
# S1 AC8: a hub can delegate: bin/secret (and bin/keys through it) call ade-secrets when installed. The delegation
# block is taken from docs/contract.md itself, so the documented contract is the tested one.
. "$(dirname "$0")/lib.sh"
CONTRACT="$ROOT/docs/contract.md"
block="$(sed -n '/^# >>> ade-secrets delegation/,/^# <<< ade-secrets delegation/p' "$CONTRACT" 2>/dev/null)"
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
check "docs/contract.md has the bin/secret delegation block" [ -n "$block" ]

# a hub-shaped bin/secret: the documented block, then the hub's own (builtin) behaviour
mkdir -p "$T/hub/bin" "$T/fakeade"
{ printf '#!/bin/bash\nset -u\n'; printf '%s\n' "$block"; printf 'echo "builtin $*"\n'; } > "$T/hub/bin/secret"
chmod +x "$T/hub/bin/secret"
cat > "$T/fakeade/ade-secrets" <<'EOF'
#!/bin/bash
echo "ade-secrets $*" >> "$FAKE_STATE/ade.log"
[ "${FAKE_REFUSE:-}" = 1 ] && { echo "refused" >&2; exit 3; }
[ "$1 ${2:-}" = "list --names" ] && printf 'alpha\nbeta\n'
exit 0
EOF
chmod +x "$T/fakeade/ade-secrets"
hub() { : > "$T/state/ade.log"; t_notty -- "$T/hub/bin/secret" "$@"; LOGGED="$(cat "$T/state/ade.log")"; }

EXTRA_ENV=("PATH=$T/fakeade:$T/bin:$T/sys")
hub --set alpha;    check "--set <name> delegates to set, enabled for the key helper" [ "$LOGGED" = "ade-secrets set alpha --helper --kind api-key --used-by hub" ]
hub alpha;          check "<name> delegates to get" [ "$LOGGED" = "ade-secrets get alpha" ]
hub --has alpha;    check "--has <name> is 0 for a stored name" eval '[ "$RC" = 0 ] && [ "$LOGGED" = "ade-secrets list --names" ] && [ -z "$OUT" ]'
hub --has gamma;    check "--has <name> is 1 for a missing name" [ "$RC" = 1 ]
hub --forget alpha; check "--forget <name> delegates to forget" [ "$LOGGED" = "ade-secrets forget alpha" ]
hub --list;         check "--list delegates to list --names" eval '[ "$LOGGED" = "ade-secrets list --names" ] && [ "$OUT" = "$(printf "alpha\nbeta")" ]'
hub;                check "no argument falls through to the hub's usage" eval '[ -z "$LOGGED" ] && [ "$OUT" = "builtin " ]'
EXTRA_ENV=("PATH=$T/fakeade:$T/bin:$T/sys" FAKE_REFUSE=1)
hub --has alpha;    check "--has passes on a refusal (exit 3), not 'missing'" [ "$RC" = 3 ]
EXTRA_ENV=("PATH=$T/fakeade:$T/bin:$T/sys" HUB_SECRETS=builtin)
hub alpha;          check "HUB_SECRETS=builtin keeps the hub's own store" eval '[ -z "$LOGGED" ] && [ "$OUT" = "builtin alpha" ]'
EXTRA_ENV=()
hub alpha;          check "without ade-secrets installed the hub's own store is used" eval '[ -z "$LOGGED" ] && [ "$OUT" = "builtin alpha" ]'

# end to end: the real ade-secrets behind the hub's bin/secret, as Claude Code's apiKeyHelper runs it
mkdir -p "$T/realade"; ln -s "$BIN" "$T/realade/ade-secrets"
EXTRA_ENV=("PATH=$T/realade:$T/bin:$T/sys")
t_tty "expect value for openai" "sleep 0.2" "send fixture-value-contract-1\n" -- "$T/hub/bin/secret" --set openai
check "end to end: the hub stores a key through ade-secrets" [ "$RC" = 0 ]
t_notty -- @claude /bin/sh -c "HUB=$T/hub $T/hub/bin/secret openai"
check "end to end: the hub's apiKeyHelper line gets the key" eval '[ "$RC" = 0 ] && [ "$OUT" = fixture-value-contract-1 ]'
EXTRA_ENV=("PATH=$T/realade:$T/bin:$T/sys" CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1)
t_notty -- @claude /bin/bash -c "$T/hub/bin/secret openai"
check "end to end: an agent's Bash tool gets nothing through the hub" eval '[ "$RC" = 3 ] && [ -z "$OUT" ]'
t_notty -- @claude /bin/bash -c "$T/hub/bin/secret --has openai"
check "end to end: presence checks refuse inside an agent too" [ "$RC" = 3 ]
t_done
