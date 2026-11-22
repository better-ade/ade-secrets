#!/bin/bash
# Re-creating a Keychain item (its trusted list changes with the helper flag) never loses the secret: the old value is
# read into memory first (a closed item asks in the allow dialog; Deny changes nothing), the item is deleted and added
# afresh, and when that add fails the old item is put back as it was, with its old trusted list.
. "$(dirname "$0")/lib.sh"
acl() { cat "$T/state/keychain/ade-secrets/$1.acl" 2>/dev/null; }
kc() { cat "$T/state/keychain/ade-secrets/$1" 2>/dev/null; }
meta_helper() { awk -F'\t' -v n="$1" '$1 == n { print $7 }' "$STORE/meta"; }

t_setup security xclip; STORE_KIND=keychain CLIP_KIND=xclip
t_set closed 'fixture-value-rc-1'
t_set opened 'fixture-value-rc-2' --helper
check "two entries, one closed and one for the helper" eval '[ "$(acl closed)" = closed ] && [ "$(acl opened)" = security ]'

# the success path
t_set closed 'fixture-value-rc-3' --helper
check "re-create (closed -> helper) succeeds: new value, security trusted, flag recorded" eval '[ "$RC" = 0 ] && [ "$(kc closed)" = fixture-value-rc-3 ] && [ "$(acl closed)" = security ] && [ "$(meta_helper closed)" = yes ]'
t_set closed 'fixture-value-rc-4' --no-helper
check "re-create (helper -> closed) succeeds: new value, no application trusted" eval '[ "$RC" = 0 ] && [ "$(kc closed)" = fixture-value-rc-4 ] && [ "$(acl closed)" = closed ] && [ "$(meta_helper closed)" = no ]'

# the add fails after the old item is deleted: the old one is put back
EXTRA_ENV=(FAKE_FAIL_ADD=once); t_set closed 'fixture-value-rc-5' --helper; EXTRA_ENV=()
check "a failed add during re-create is reported (exit 1)" eval '[ "$RC" = 1 ] && has "$OUT" "kept"'
check "... and the old item is back: old value, old trusted list, old flag" eval '[ "$(kc closed)" = fixture-value-rc-4 ] && [ "$(acl closed)" = closed ] && [ "$(meta_helper closed)" = no ]'
rm -f "$T/state/add-failed"
EXTRA_ENV=(FAKE_FAIL_ADD=once); t_set opened 'fixture-value-rc-6' --no-helper; EXTRA_ENV=()
check "a failed add while closing a helper entry puts the helper item back" eval '[ "$RC" = 1 ] && [ "$(kc opened)" = fixture-value-rc-2 ] && [ "$(acl opened)" = security ] && [ "$(meta_helper opened)" = yes ]'

# Deny on the read of the old value: nothing is deleted
EXTRA_ENV=(FAKE_DENY=1); t_set closed 'fixture-value-rc-7' --helper; EXTRA_ENV=()
check "Deny on reading the old value: nothing deleted, nothing changed" eval '[ "$RC" = 1 ] && [ "$(kc closed)" = fixture-value-rc-4 ] && [ "$(acl closed)" = closed ]'

check "no value in an argument, the environment or a file outside the store" eval 'for i in 1 2 3 4 5 6 7; do no_leak fixture-value-rc-$i || exit 1; done'
check "the old value is held in memory only: no temporary file in the store folder" eval '[ -z "$(ls -A "$T/tmp")" ] && [ -z "$(find "$STORE" -type f ! -name meta ! -name store)" ]'
t_done
