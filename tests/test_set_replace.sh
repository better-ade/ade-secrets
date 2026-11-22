#!/bin/bash
# S3 AC3 set_asks_before_replace: `set` on a name that exists in the current store asks on the terminal, before the
# value prompt (and before the age passphrase): `replace <name> (rotated <age> ago)? [y/N] ` (docs/contract-v2.md,
# "`set`: asking before a replace"). It names the entry (scope and key, never a value); no answer, or anything but y,
# ends with exit 1 and `kept <name> unchanged`; a new name is stored as before, without the question.
. "$(dirname "$0")/lib.sh"
N=acme-ops.anthropic-api-key
val() {
  case "$STORE_KIND" in
    keychain) cat "$T/state/keychain/ade-secrets/$1" 2>/dev/null ;;
    pass) cat "$T/state/pass/ade-secrets/$1" 2>/dev/null ;;
    age) cat "$STORE/age/entries/$1.age" 2>/dev/null | cksum ;;
  esac
}
line() { grep "^$1	" "$STORE/meta"; }
# ask <answer-steps...> -- <set options>: set $N, answering the question with the given steps
ask() {
  local steps=()
  while [ "$1" != -- ]; do steps+=("$1"); shift; done; shift
  t_tty "expect replace " "sleep 0.1" ${steps[@]+"${steps[@]}"} -- @ set "$N" ${1+"$@"}
}
for kind in keychain pass age; do
  t_setup; STORE_KIND=$kind CLIP_KIND=xclip
  [ $kind = age ] && t_unlock
  t_set "$N" fixture-value-rp-1
  check "set_asks_before_replace: $kind: a new name is stored, without the question" eval '[ "$RC" = 0 ] && hasnt "$OUT" replace && has "$OUT" "stored $N"'
  # rotated 12 days ago, as in the contract's example
  awk -F'\t' -v OFS='\t' -v t=$(( $(date +%s) - 12 * 86400 - 60 )) '{ $6 = t; print }' "$STORE/meta" > "$T/meta.new" && cat "$T/meta.new" > "$STORE/meta"
  V="$(val "$N")" M="$(line "$N")"

  ask "send n\n" --
  check "set_asks_before_replace: $kind: it asks, naming the entry and when it was rotated" \
    eval 'printf "%s\n" "$OUT" | grep -q -F "replace $N (rotated 12d ago)? [y/N] "'
  check "set_asks_before_replace: $kind: n: exit 1, 'kept ... unchanged', no value prompt" \
    eval '[ "$RC" = 1 ] && has "$OUT" "kept $N unchanged" && hasnt "$OUT" "value for"'
  check "set_asks_before_replace: $kind: ... the value and meta are unchanged" eval '[ "$(val "$N")" = "$V" ] && [ "$(line "$N")" = "$M" ]'
  [ $kind = age ] && check "set_asks_before_replace: age: it asks before the passphrase" eval 'hasnt "$OUT" "Enter passphrase"'

  ask "send \n" --
  check "set_asks_before_replace: $kind: an empty answer keeps it" eval '[ "$RC" = 1 ] && has "$OUT" "kept $N unchanged" && [ "$(val "$N")" = "$V" ] && [ "$(line "$N")" = "$M" ]'
  ask "send \x04" --
  check "set_asks_before_replace: $kind: no answer (end of input) keeps it" eval '[ "$RC" = 1 ] && has "$OUT" "kept $N unchanged" && [ "$(val "$N")" = "$V" ] && [ "$(line "$N")" = "$M" ]'
  ask "send yes\n" --
  check "set_asks_before_replace: $kind: anything but y keeps it ('yes')" eval '[ "$RC" = 1 ] && [ "$(val "$N")" = "$V" ]'
  ask "send Y\n" --
  check "set_asks_before_replace: $kind: ... and 'Y'" eval '[ "$RC" = 1 ] && [ "$(val "$N")" = "$V" ]'
  ask "send n\n" -- --helper
  check "set_asks_before_replace: $kind: a change of mark asks too, and n keeps the mark" \
    eval '[ "$RC" = 1 ] && has "$OUT" "replace $N" && [ "$(line "$N")" = "$M" ]'
  clip_put fixture-value-rp-clip
  ask "send n\n" -- --clipboard
  check "set_asks_before_replace: $kind: with --clipboard, n keeps the entry and clears the clipboard" \
    eval '[ "$RC" = 1 ] && [ "$(val "$N")" = "$V" ] && [ -z "$(clip)" ]'

  _t_pw
  ask "send y\n" ${PW_STEPS[@]+"${PW_STEPS[@]}"} "expect value for $N" "sleep 0.2" "send fixture-value-rp-2\n" --
  check "set_asks_before_replace: $kind: y: the value prompt follows and the value is replaced" \
    eval '[ "$RC" = 0 ] && has "$OUT" "stored $N" && [ "$(val "$N")" != "$V" ]'
  check "set_asks_before_replace: $kind: the question and its answer never show a value" eval 'hasnt "$OUT" fixture-value-rp'
  [ $kind = keychain ] && check "set_asks_before_replace: keychain: ... with the new value" [ "$(val "$N")" = fixture-value-rp-2 ]
  [ $kind = pass ] && check "set_asks_before_replace: pass: ... with the new value" [ "$(val "$N")" = fixture-value-rp-2 ]
  t_copy "$N" --for 30
  check "set_asks_before_replace: $kind: ... and copy returns it" [ "$(clip)" = fixture-value-rp-2 ]
  check "set_asks_before_replace: $kind: nothing leaked" eval 'no_leak fixture-value-rp-1 && no_leak fixture-value-rp-2'
  t_cleanup
done
t_done
