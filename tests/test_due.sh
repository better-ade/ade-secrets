#!/bin/bash
# S3 AC6 list_due_names_only: `list --due [--scope S]` prints one name per line, sorted, for entries whose last
# rotation is ADE_SECRETS_ROTATE_DAYS (default 90, the vault's rule) days old or more, and nothing else; with
# --scope the names lose the `S.` prefix. It is guarded like `list` (docs/contract-v2.md, "Release files and version").
. "$(dirname "$0")/lib.sh"
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
for n in acme-ops.old-key acme-ops.new-key acme-ops.edge-key beta-hub.old-key legacy fresh; do t_set "$n" "fixture-value-due-$n"; done
day=86400 now="$(date +%s)"
# rotated: 100, 1, exactly 90 (and a minute), 95, 200 days ago; fresh now
awk -F'\t' -v OFS='\t' -v now="$now" -v d=$day '
  $1 == "acme-ops.old-key" { $6 = now - 100 * d } $1 == "acme-ops.new-key" { $6 = now - 1 * d }
  $1 == "acme-ops.edge-key" { $6 = now - 90 * d - 60 } $1 == "beta-hub.old-key" { $6 = now - 95 * d }
  $1 == "legacy" { $6 = now - 200 * d } { print }' "$STORE/meta" > "$T/meta.new" && cat "$T/meta.new" > "$STORE/meta"
# a terminal, with stdout kept apart from the screen
due() { t_tty -- /bin/sh -c "'$BIN' list --due $* > '$T/run/due'"; D="$(cat "$T/run/due")"; }

due
check "list_due_names_only: past 90 days, full names, sorted, nothing else" \
  eval '[ "$RC" = 0 ] && [ "$D" = "$(printf "acme-ops.edge-key\nacme-ops.old-key\nbeta-hub.old-key\nlegacy")" ]'
due --scope acme-ops
check "list_due_names_only: --scope keeps one scope, names without the scope" eval '[ "$RC" = 0 ] && [ "$D" = "$(printf "edge-key\nold-key")" ]'
due --scope nobody
check "list_due_names_only: none due: exit 0, empty" eval '[ "$RC" = 0 ] && [ -z "$D" ]'
EXTRA_ENV=(ADE_SECRETS_ROTATE_DAYS=99); due
check "list_due_names_only: ADE_SECRETS_ROTATE_DAYS sets the age" eval '[ "$D" = "$(printf "acme-ops.old-key\nlegacy")" ]'
EXTRA_ENV=(ADE_SECRETS_ROTATE_DAYS=1); due
check "list_due_names_only: ... one day: all but the fresh one" eval '[ "$D" = "$(printf "acme-ops.edge-key\nacme-ops.new-key\nacme-ops.old-key\nbeta-hub.old-key\nlegacy")" ]'
for bad in 0 -5 abc 99999 ''; do
  EXTRA_ENV=("ADE_SECRETS_ROTATE_DAYS=$bad"); due
  check "list_due_names_only: ADE_SECRETS_ROTATE_DAYS='$bad' falls back to 90, as in the vault" \
    eval '[ "$RC" = 0 ] && [ "$D" = "$(printf "acme-ops.edge-key\nacme-ops.old-key\nbeta-hub.old-key\nlegacy")" ]'
done
EXTRA_ENV=()
due --scope acme-ops --names
check "list_due_names_only: --due and --names together are a usage error" [ "$RC" = 2 ]
due --scope Bad_Scope
check "list_due_names_only: a scope that breaks the rules is refused" [ "$RC" = 2 ]
check "list_due_names_only: never a value" eval 'no_leak fixture-value-due'

# guarded like list
for v in CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_ENTRYPOINT=cli; do
  EXTRA_ENV=("$v"); t_tty -- @ list --due
  check "list_due_names_only: refused (3) with ${v%%=*}" eval '[ "$RC" = 3 ] && hasnt "$OUT" old-key'
done
EXTRA_ENV=()
t_tty -- @claude @ list --due
check "list_due_names_only: refused (3) with a claude ancestor" eval '[ "$RC" = 3 ] && hasnt "$OUT" old-key'
t_notty -- @ list --due
check "list_due_names_only: refused (3) without a terminal" eval '[ "$RC" = 3 ] && [ -z "$OUT" ]'
t_done
