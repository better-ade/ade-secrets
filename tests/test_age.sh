#!/bin/bash
# S1 AC6: the age store is encrypted at rest, locks after idle, refuses copy while locked.
# Review fix: the store keeps no session at all (no plaintext identity on disk, ever): set and copy ask for the
# passphrase each time, so outside the vault the store is always locked. The recipient is derived from the identity.
. "$(dirname "$0")/lib.sh"
V1='fixture-value-age-1'
t_setup; STORE_KIND=age CLIP_KIND=xclip

t_unlock
check "unlock on a new store creates a passphrase-protected identity" eval '[ "$RC" = 0 ] && [ -s "$STORE/age/identity.age" ]'
check "the identity is encrypted at rest" eval '! grep -q FAKE-AGE-IDENTITY "$STORE/age/identity.age"'
t_set alpha "$V1"
check "set asks for the passphrase, then the value" [ "$RC" = 0 ]
b64="$(printf '%s' "$V1" | base64)"
check "the entry is encrypted at rest" eval '[ -s "$STORE/age/entries/alpha.age" ] && ! grep -r -q -F -- "$V1" "$STORE" && ! grep -r -q -F -- "$b64" "$STORE"'
check "the store folder is private" eval '[ "$(ls -ld "$STORE" | cut -c1-10)" = drwx------ ]'
check "no session folder, no recipient file" eval '[ ! -e "$STORE/session" ] && [ ! -e "$STORE/age/recipient" ]'
check "no plaintext identity anywhere on disk" eval '! grep -r -q FAKE-AGE-IDENTITY "$T/home" "$T/tmp" "$T/run"'

t_copy alpha --for 30
check "copy with the passphrase" eval '[ "$RC" = 0 ] && [ "$(clip)" = "$V1" ]'
clip_put 'fixture-untouched'
t_tty "expect Enter passphrase" "sleep 0.1" "send not-the-passphrase\n" -- @ copy alpha
check "copy refuses with a wrong passphrase (the store is locked)" eval '[ "$RC" = 5 ] && [ "$(clip)" = fixture-untouched ]'
t_tty -- @ status
check "status says the store keeps no session" eval 'has "$OUT" "no session"'
t_tty -- @ lock
check "lock has nothing to close" eval '[ "$RC" = 0 ] && has "$OUT" "no session"'

printf 'age1fixtureattackerrecipient\n' > "$STORE/age/recipient"
: > "$T/state/calls.log"
t_set beta 'fixture-value-age-2'
check "the recipient comes from the identity, never from a file in the store" eval 'grep -q "age1fakerecipientfortests" "$T/state/calls.log" && ! grep -q "argv=.*age1fixtureattacker" "$T/state/calls.log"'
t_tty "expect Enter passphrase" "sleep 0.1" "send not-the-passphrase\n" -- @ set gamma
check "set refuses with a wrong passphrase" eval '[ "$RC" = 5 ] && [ ! -e "$STORE/age/entries/gamma.age" ]'

t_set helped 'fixture-value-age-3' --helper
EXTRA_ENV=(CLAUDE_CODE_ENTRYPOINT=cli)
t_notty -- @claude /bin/sh -c "\"$BIN\" get helped"
check "the age store cannot serve the key helper (no session to read with)" eval '[ "$RC" = 5 ] && [ -z "$OUT" ]'
EXTRA_ENV=()
check "nothing leaked" eval 'no_leak "$V1" && no_leak fixture-value-age-2'
t_done
