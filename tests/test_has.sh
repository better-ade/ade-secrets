#!/bin/bash
# S3 AC4 has_presence_only: `has <name>` prints nothing and exits 0 when the entry exists, 1 when it does not; it
# answers without a terminal and inside an agent session; it never reads a value: it reads meta, then the store's
# record of the item only (Keychain attributes without -w, the pass file, the age file), so a closed Keychain item
# raises no dialog (docs/contract-v2.md, "`has`: presence without a value"). One bit about a name the caller already
# has: no listing, no pattern, no prefix.
# S3 AC5 has_other_exits: every other exit is the contract's code with one line on stderr: no store chosen (2), a
# locked (not yet created) age store (5), a bad name (2); and meta listing an entry the store lacks is 1, with the
# contract's line.
. "$(dirname "$0")/lib.sh"
N=acme-ops.anthropic-api-key P=acme-ops.zai-api-key
SESSION="CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_PID=1 CLAUDE_CODE_SESSION_ID=fixture CLAUDE_PROJECT_DIR=/tmp"
# has_in <context> <name>: run has as that caller; RC, OUT (stdout), ERR (stderr)
has_in() {
  case "$1" in
    terminal) t_tty -- /bin/sh -c "'$BIN' has '$2' > '$T/run/has.out'"; ERR="$OUT"; OUT="$(cat "$T/run/has.out")" ;;
    service) t_notty -- @ has "$2" ;;
    agent) EXTRA_ENV=($SESSION); t_notty -- @claude /bin/bash -c "'$BIN' has '$2'"; EXTRA_ENV=() ;;
    agent-tty) EXTRA_ENV=($SESSION); t_tty -- @claude /bin/bash -c "'$BIN' has '$2' > '$T/run/has.out'"; ERR="$OUT"; OUT="$(cat "$T/run/has.out")"; EXTRA_ENV=() ;;
    helper) EXTRA_ENV=(CLAUDE_CODE_ENTRYPOINT=cli); t_notty -- @claude /bin/sh -c "'$BIN' has '$2'"; EXTRA_ENV=() ;;
  esac
}
# reads_no_value <kind>: the calls since the log was emptied read no value and raised no dialog
reads_no_value() {
  case "$1" in
    keychain) ! grep -q "^DIALOG" "$T/state/calls.log" && ! grep "^CALL security" "$T/state/calls.log" | grep -q -e "'-w'" -e "'-i'" -e "dump" ;;
    pass) ! grep -q "^CALL pass" "$T/state/calls.log" ;;
    age) ! grep -q "^CALL age" "$T/state/calls.log" ;;
  esac
}

for kind in keychain pass age; do
  t_setup; STORE_KIND=$kind CLIP_KIND=xclip
  [ $kind = age ] && t_unlock
  t_set "$N" fixture-value-has-1 --helper
  t_set "$P" fixture-value-has-2          # a closed item in the Keychain: a read of its value is the macOS dialog
  t_set acme-ops fixture-value-has-3
  for ctx in terminal service agent agent-tty helper; do
    : > "$T/state/calls.log"
    has_in $ctx "$P"
    check "has_presence_only: $kind: $ctx: present: exit 0, nothing printed" eval '[ "$RC" = 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]'
    check "has_presence_only: $kind: $ctx: ... and no value read, no dialog" reads_no_value $kind
    has_in $ctx acme-ops.missing-key
    check "has_presence_only: $kind: $ctx: absent: exit 1, nothing printed" eval '[ "$RC" = 1 ] && [ -z "$OUT" ] && [ -z "$ERR" ]'
  done
  [ $kind = keychain ] && check "has_presence_only: keychain: it asks the Keychain for attributes only" \
    eval 'grep "^CALL security" "$T/state/calls.log" | grep -q "find-generic-password" '
  : > "$T/state/calls.log"
  has_in service "$N"
  check "has_presence_only: $kind: a helper entry is present too" eval '[ "$RC" = 0 ] && reads_no_value $kind'
  # one bit about the name given, nothing else
  for probe in acme-ops.anthropic acme-ops.anthropic-api-key.v2 acme-ops.ANTHROPIC-API-KEY anthropic-api-key acme-ops.zai-api-key2; do
    has_in service "$probe"
    check "has_presence_only: $kind: '$probe' is absent (no prefix, no case folding, no other scope)" eval '[ "$RC" = 1 ] && [ -z "$OUT$ERR" ]'
  done
  for probe in 'acme-ops.*' 'acme-ops.zai?api-key' 'acme-ops.[a-z]*' 'acme-ops.' ''; do
    has_in service "$probe"
    check "has_presence_only: $kind: '$probe' is no pattern: refused as a name (2)" eval '[ "$RC" = 2 ] && [ -z "$OUT" ]'
  done
  t_notty -- @ has "$P" "$N"
  check "has_presence_only: $kind: one name only" eval '[ "$RC" = 2 ] && [ -z "$OUT" ]'
  t_notty -- @ has
  check "has_presence_only: $kind: a name is needed" eval '[ "$RC" = 2 ] && [ -z "$OUT" ]'
  t_tty "expect type the name" "send $P\n" -- @ forget "$P"
  has_in service "$P"
  check "has_presence_only: $kind: after forget it is absent" [ "$RC" = 1 ]
  EXTRA_ENV=("BASH_ENV=$T/input/none")
  t_notty -- @ has "$N"
  check "has_presence_only: $kind: the start-up check still refuses (3)" eval '[ "$RC" = 3 ] && [ -z "$OUT" ] && has "$ERR" BASH_ENV'
  EXTRA_ENV=()
  check "has_presence_only: $kind: nothing leaked" eval 'no_leak fixture-value-has-1 && no_leak fixture-value-has-2'
  t_cleanup
done

# ---- AC5: every other exit, one line on stderr, nothing on stdout
one_line() { [ -z "$OUT" ] && [ "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')" = 1 ] && has "$ERR" "ade-secrets: "; }
t_setup; CLIP_KIND=xclip; STORE_KIND=
t_notty -- @ has "$N"
check "has_other_exits: no store chosen: 2, one line" eval '[ "$RC" = 2 ] && one_line && has "$ERR" "choose a store"'
EXTRA_ENV=($SESSION); t_notty -- @claude /bin/bash -c "'$BIN' has '$N'"; EXTRA_ENV=()
check "has_other_exits: ... the same inside an agent session" eval '[ "$RC" = 2 ] && one_line'
STORE_KIND=keychain
t_set "$N" fixture-value-has-4
STORE_KIND=pass
t_notty -- @ has "$N"
check "has_other_exits: an ADE_SECRETS_STORE that differs from the record: 2, one line" eval '[ "$RC" = 2 ] && one_line'
STORE_KIND=
t_notty -- @ has 'Acme.key'
check "has_other_exits: a bad name: 2, one line" eval '[ "$RC" = 2 ] && one_line'
rm -f "$T/state/keychain/ade-secrets/$N" "$T/state/keychain/ade-secrets/$N.acl"
t_notty -- @ has "$N"
check "has_other_exits: meta lists it but the store has no item: 1, the contract's line" \
  eval '[ "$RC" = 1 ] && one_line && has "$ERR" "meta lists $N but the keychain store has no item; set it again"'
chmod 666 "$STORE/meta"
t_notty -- @ has "$N"
check "has_other_exits: a meta others can write is refused: v1's 1, with one line (absent has none)" eval '[ "$RC" = 1 ] && one_line && has "$ERR" meta'
chmod 600 "$STORE/meta"
t_remove_fake security
t_notty -- @ has "$N"
check "has_other_exits: the store's tool missing: v1's 1, with one line" eval '[ "$RC" = 1 ] && one_line && has "$ERR" security'
t_cleanup

t_setup; CLIP_KIND=xclip; STORE_KIND=age
t_notty -- @ has "$N"
check "has_other_exits: the age store not created (locked): 5, one line" eval '[ "$RC" = 5 ] && one_line && has "$ERR" unlock'
t_unlock
t_set "$N" fixture-value-has-5
: > "$T/state/calls.log"
t_notty -- @ has "$N"
check "has_other_exits: the age store, once created, answers without its passphrase" eval '[ "$RC" = 0 ] && [ -z "$OUT$ERR" ] && ! grep -q "^CALL age" "$T/state/calls.log"'
rm -f "$STORE/age/entries/$N.age"
t_notty -- @ has "$N"
check "has_other_exits: age: meta lists it but the store has no item: 1, the contract's line" \
  eval '[ "$RC" = 1 ] && one_line && has "$ERR" "meta lists $N but the age store has no item; set it again"'
t_cleanup

t_setup; CLIP_KIND=xclip; STORE_KIND=pass
t_set "$N" fixture-value-has-6
rm -f "$T/home/.password-store/ade-secrets/$N.gpg"
t_notty -- @ has "$N"
check "has_other_exits: pass: meta lists it but the store has no item: 1, the contract's line" \
  eval '[ "$RC" = 1 ] && one_line && has "$ERR" "meta lists $N but the pass store has no item; set it again"'
t_done
