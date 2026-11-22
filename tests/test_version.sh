#!/bin/bash
# S3 AC8 version_in_script: the version is one line in the script itself (ADE_SECRETS_VERSION=X.Y.Z), held equal to
# VERSION by this test, and `--version` (or `version`) prints it without reading any other file, in every context,
# after the start-up check (docs/contract-v2.md, "Release files and version": VERSION is not a release file).
. "$(dirname "$0")/lib.sh"
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
lines="$(grep -c '^ADE_SECRETS_VERSION=' "$BIN")"
SV="$(sed -n 's/^ADE_SECRETS_VERSION=\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' "$BIN")"
check "version_in_script: the script carries one ADE_SECRETS_VERSION=X.Y.Z line" eval '[ "$lines" = 1 ] && [ -n "$SV" ]'
check "version_in_script: ... equal to VERSION" [ "$SV" = "$(cat "$ROOT/VERSION")" ]
t_notty -- @ --version
check "version_in_script: --version prints that one line" eval '[ "$RC" = 0 ] && [ "$OUT" = "$SV" ] && [ -z "$ERR" ]'
t_notty -- @ version
check "version_in_script: version prints it too" eval '[ "$RC" = 0 ] && [ "$OUT" = "$SV" ]'

# installed as a release installs it: bin/ade-secrets and lib/vault.sh, no VERSION; and next to a decoy VERSION
mkdir -p "$T/inst/bin" "$T/inst/lib" "$T/decoy/bin"
cp "$BIN" "$T/inst/bin/ade-secrets"; cp "$ROOT/lib/vault.sh" "$T/inst/lib/vault.sh"
cp "$BIN" "$T/decoy/bin/ade-secrets"; echo 9.9.9 > "$T/decoy/VERSION"
t_notty -- "$T/inst/bin/ade-secrets" --version
check "version_in_script: with no VERSION file installed it still prints the version" eval '[ "$RC" = 0 ] && [ "$OUT" = "$SV" ]'
t_notty -- "$T/decoy/bin/ade-secrets" --version
check "version_in_script: a VERSION file next to it is not read" eval '[ "$RC" = 0 ] && [ "$OUT" = "$SV" ]'
mkdir -p "$T/link"; ln -s "$T/inst/bin/ade-secrets" "$T/link/ade-secrets"
t_notty -- "$T/link/ade-secrets" --version
check "version_in_script: ... and through a symlink on PATH" eval '[ "$RC" = 0 ] && [ "$OUT" = "$SV" ]'

# every context: a terminal, an agent session, the key helper; still after the start-up check
t_tty -- @ --version
check "version_in_script: in a terminal" eval '[ "$RC" = 0 ] && [ "$OUT" = "$SV" ]'
EXTRA_ENV=(CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1); t_notty -- @claude /bin/bash -c "'$BIN' --version"
check "version_in_script: inside an agent session" eval '[ "$RC" = 0 ] && [ "$OUT" = "$SV" ]'
EXTRA_ENV=(CLAUDE_CODE_ENTRYPOINT=cli); t_notty -- @claude /bin/sh -c "'$BIN' --version"
check "version_in_script: from the key helper's context" eval '[ "$RC" = 0 ] && [ "$OUT" = "$SV" ]'
EXTRA_ENV=("BASH_ENV=$T/input/none"); t_notty -- @ --version
check "version_in_script: the start-up check comes first" eval '[ "$RC" = 3 ] && [ -z "$OUT" ]'
EXTRA_ENV=()
check "version_in_script: --version reads no VERSION file" eval '! grep -E -q "/VERSION|[<] *[^ ]*VERSION|cat [^|;]*VERSION" "$BIN"'
t_done
