#!/bin/bash
# S3 AC1 scope_names: a name may carry a scope, <scope>.<key> (docs/contract-v2.md, "Names and scopes"); every command
# takes it; a name that breaks the rules is refused (exit 2) before the store is touched. Each store keeps the full
# name flat (the Keychain account, the pass file, the age file), so a dot or a scope equal to another entry's name
# cannot confuse two entries.
# S3 AC2 scope_list_and_vault: list and the vault show a SCOPE column and can be limited to one scope; entries made
# by 0.3.0 (no scope) show "-" and are left exactly as they are.
. "$(dirname "$0")/lib.sh"
N=acme-ops.anthropic-api-key
kc() { cat "$T/state/keychain/ade-secrets/$1" 2>/dev/null; }
stored_at() { # <kind> <name>: the store's own file for that entry
  case "$1" in
    keychain) printf '%s\n' "$T/state/keychain/ade-secrets/$2" ;;
    pass) printf '%s\n' "$T/home/.password-store/ade-secrets/$2.gpg" ;;
    age) printf '%s\n' "$STORE/age/entries/$2.age" ;;
  esac
}
helper_get() { t_notty -- @claude /bin/sh -c "'$BIN' get '$1'"; }
forget() { t_tty "expect type the name" "send $1\n" -- @ forget "$1"; }
# the stores' own state (the clipboard is left out: copy's timed clearers run on their own clock)
state_sum() { (cd "$T" && find state/keychain state/pass home/.password-store home/.ade-secrets -type f 2>/dev/null | sort | xargs cat 2>/dev/null) | cksum; }

# ---- AC1, every store
for kind in keychain pass age; do
  t_setup; STORE_KIND=$kind CLIP_KIND=xclip
  [ $kind = age ] && t_unlock
  t_set "$N" fixture-value-scope-1 --helper
  check "scope_names: $kind: set takes a scoped name" eval '[ "$RC" = 0 ] && [ -f "$(stored_at $kind "$N")" ]'
  t_set acme-ops fixture-value-scope-2
  check "scope_names: $kind: an entry named like a scope is its own entry" eval '[ "$RC" = 0 ] && [ -f "$(stored_at $kind acme-ops)" ]'
  t_set acme-ops.anthropic-api-key.v2 fixture-value-scope-3
  check "scope_names: $kind: a key may hold more dots" eval '[ "$RC" = 0 ] && [ -f "$(stored_at $kind acme-ops.anthropic-api-key.v2)" ]'
  t_copy "$N" --for 30
  check "scope_names: $kind: copy takes it, and each name keeps its own value" [ "$(clip)" = fixture-value-scope-1 ]
  t_copy acme-ops --for 30
  check "scope_names: $kind: ... the entry named like the scope too" [ "$(clip)" = fixture-value-scope-2 ]
  t_copy acme-ops.anthropic-api-key.v2 --for 30
  check "scope_names: $kind: ... and the longer name" [ "$(clip)" = fixture-value-scope-3 ]
  t_notty -- @ has "$N"
  check "scope_names: $kind: has takes it" [ "$RC" = 0 ]
  if [ $kind != age ]; then
    helper_get "$N"
    check "scope_names: $kind: get takes it" eval '[ "$RC" = 0 ] && [ "$OUT" = fixture-value-scope-1 ]'
  fi
  t_tty -- @ list --names --scope acme-ops
  check "scope_names: $kind: list --scope takes the scope" eval '[ "$RC" = 0 ] && [ "$OUT" = "$(printf "anthropic-api-key\nanthropic-api-key.v2")" ]'
  forget acme-ops
  check "scope_names: $kind: forget takes a name, and leaves the scoped entries" eval '[ "$RC" = 0 ] && [ ! -e "$(stored_at $kind acme-ops)" ] && [ -f "$(stored_at $kind "$N")" ]'
  forget "$N"
  check "scope_names: $kind: forget takes a scoped name" eval '[ "$RC" = 0 ] && [ ! -e "$(stored_at $kind "$N")" ] && [ -f "$(stored_at $kind acme-ops.anthropic-api-key.v2)" ]'
  S40=aaaaaaaaaabbbbbbbbbbccccccccccdddddddddd
  t_set "$S40.k" fixture-value-scope-4
  check "scope_names: $kind: a scope of 40 characters is taken" [ "$RC" = 0 ]
  t_set acme-ops.Anthropic-Api-Key.v2 fixture-value-scope-5
  check "scope_names: $kind: v1's case rule holds for scoped names" eval '[ "$RC" = 2 ] && has "$OUT" "only in case"'

  # refused before the store is touched: no store tool is called, nothing in the fake stores changes
  for bad in Acme-ops.k ACME.k acme_ops.k -acme.k acme-ops. acme-ops..k acme-ops.-k acme-ops._k ".k" "acme ops.k" \
             'acme-ops.k*' 'acme-ops.k?' "${S40}e.k" "$S40.$(printf '%025d' 0)" 'acme/ops.k' 'acme-ops.k/../x'; do
    before="$(state_sum)"; : > "$T/state/calls.log"
    t_tty -- @ set "$bad"
    r_set=$RC; o_set=$OUT
    t_tty -- @ copy "$bad"; r_copy=$RC
    t_tty -- @ forget "$bad"; r_forget=$RC
    t_notty -- @ has "$bad"; r_has=$RC
    helper_get "$bad"; r_get=$RC
    check "scope_names: $kind: '$bad' is refused (2) by set, copy, forget, has and get, before any store call" \
      eval '[ "$r_set $r_copy $r_forget $r_has $r_get" = "2 2 2 2 2" ] && hasnt "$o_set" "value for" && ! grep -q -e "^CALL security" -e "^CALL pass" -e "^CALL age" "$T/state/calls.log" && [ "$(state_sum)" = "$before" ]'
  done
  t_tty -- @ list --scope Acme_Ops
  check "scope_names: $kind: list refuses a scope that breaks the rules" [ "$RC" = 2 ]
  check "scope_names: $kind: nothing leaked (get's own output aside)" eval 'no_leak fixture-value-scope-2 && no_leak fixture-value-scope-3'
  t_cleanup
done

# ---- AC2: the SCOPE column, one scope, and entries made by 0.3.0
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
T_TIMEOUT=60
t_set openai fixture-value-sl-1 --kind api-key --used-by agents --helper
V1_LINE="$(grep "^openai	" "$STORE/meta")"
V1_SUM="$(cat "$T/state/keychain/ade-secrets/openai" "$T/state/keychain/ade-secrets/openai.acl" | cksum)"
check "scope_list_and_vault: a 0.3.0 entry has v1's seven fields" [ "$(printf '%s\n' "$V1_LINE" | awk -F'\t' '{ print NF }')" = 7 ]
t_set "$N" fixture-value-sl-2 --kind api-key --used-by hub:acme-ops --helper
t_set acme-ops.zai-api-key fixture-value-sl-3
t_set beta-hub.anthropic-api-key fixture-value-sl-4
t_tty -- /bin/sh -c "'$BIN' list > '$T/run/list'"
L="$(cat "$T/run/list")"
check "scope_list_and_vault: list has the columns SCOPE NAME KIND USED-BY AGE USE" eval '[ "$(printf "%s\n" "$L" | head -1 | tr -s " ")" = "SCOPE NAME KIND USED-BY AGE USE" ]'
row() { printf '%s\n' "$L" | awk -v s="$1" -v n="$2" '$1 == s && $2 == n { $5 = "AGE"; print }'; }
check "scope_list_and_vault: a scoped entry shows its scope, the name without it, and its use" \
  [ "$(row acme-ops anthropic-api-key)" = "acme-ops anthropic-api-key api-key hub:acme-ops AGE helper" ]
check "scope_list_and_vault: ... one not marked shows - as its use" [ "$(row acme-ops zai-api-key)" = "acme-ops zai-api-key secret - AGE -" ]
check "scope_list_and_vault: a 0.3.0 entry shows - as its scope" [ "$(row - openai)" = "- openai api-key agents AGE helper" ]
check "scope_list_and_vault: list never shows a value" eval 'hasnt "$L" fixture-value'
t_tty -- /bin/sh -c "'$BIN' list --scope acme-ops > '$T/run/list'"
L="$(cat "$T/run/list")"
check "scope_list_and_vault: list --scope keeps that scope only" \
  eval '[ "$(printf "%s\n" "$L" | sed 1d | awk "{ print \$1 \" \" \$2 }")" = "$(printf "acme-ops anthropic-api-key\nacme-ops zai-api-key")" ]'
t_tty -- /bin/sh -c "'$BIN' list --names > '$T/run/list'"
check "scope_list_and_vault: list --names prints full names" \
  [ "$(cat "$T/run/list")" = "$(printf 'acme-ops.anthropic-api-key\nacme-ops.zai-api-key\nbeta-hub.anthropic-api-key\nopenai')" ]
t_tty -- /bin/sh -c "'$BIN' list --names --scope beta-hub > '$T/run/list'"
check "scope_list_and_vault: list --names --scope prints the names without the scope" [ "$(cat "$T/run/list")" = anthropic-api-key ]
t_tty -- /bin/sh -c "'$BIN' list --scope nobody > '$T/run/list'"
check "scope_list_and_vault: a scope with no entries lists none" eval '[ "$RC" = 0 ] && [ "$(sed 1d "$T/run/list")" = "" ]'

# the vault: the SCOPE column, limited to one scope, search on the full name, add a scoped name
t_tty "expect q quit" "sleep 0.3" "snap $T/run/v1" "send q" -- @ vault
S="$(screen_of "$T/run/v1")"
vrow() { printf '%s\n' "$S" | awk -v s="$1" -v n="$2" '{ sub(/^> /, "") } $1 == s && $2 == n { print $1, $2, $3, $4 }'; }
check "scope_list_and_vault: the vault has a SCOPE column" eval 'printf "%s\n" "$S" | grep -q "SCOPE *NAME *KIND *USED-BY *ROTATED"'
check "scope_list_and_vault: the vault shows each entry's scope and name" \
  eval '[ "$(vrow acme-ops anthropic-api-key)" = "acme-ops anthropic-api-key api-key hub:acme-ops" ] && [ "$(vrow - openai)" = "- openai api-key agents" ] && [ -n "$(vrow beta-hub anthropic-api-key)" ]'
t_tty "expect q quit" "sleep 0.3" "snap $T/run/v2" "send \r" "expect copied" "send q" -- @ vault --scope beta-hub
S="$(screen_of "$T/run/v2")"
check "scope_list_and_vault: vault --scope keeps that scope only" \
  eval '[ -n "$(vrow beta-hub anthropic-api-key)" ] && [ -z "$(vrow acme-ops anthropic-api-key)" ] && [ -z "$(vrow - openai)" ] && has "$S" "scope: beta-hub"'
check "scope_list_and_vault: ... and acts on the full name" [ "$(clip)" = fixture-value-sl-4 ]
t_tty -- @ vault --scope Not_A_Scope
check "scope_list_and_vault: vault --scope refuses a scope that breaks the rules" [ "$RC" = 2 ]
t_tty "expect q quit" "send /" "expect search: " "send acme-ops.zai\n" "expect search: acme-ops.zai" "sleep 0.3" "snap $T/run/v3" "send q" -- @ vault
S="$(screen_of "$T/run/v3")"
check "scope_list_and_vault: the vault's search matches the full name" eval '[ -n "$(vrow acme-ops zai-api-key)" ] && [ -z "$(vrow acme-ops anthropic-api-key)" ]'
t_tty "expect q quit" "send a" "expect name: " "send beta-hub.zai-api-key\n" "expect kind" "send \n" "expect used by" "send \n" \
  "expect value from" "send p" "expect value for beta-hub.zai-api-key" "sleep 0.2" "send fixture-value-sl-5\n" "expect stored" "send q" -- @ vault
check "scope_list_and_vault: the vault adds a scoped name" [ "$(kc beta-hub.zai-api-key)" = fixture-value-sl-5 ]
t_tty "expect q quit" "send a" "expect name: " "send Beta_Hub.x\n" "expect name is|scope" "send q" -- @ vault
check "scope_list_and_vault: ... and refuses one that breaks the rules" eval '[ ! -e "$T/state/keychain/ade-secrets/Beta_Hub.x" ]'

check "scope_list_and_vault: the 0.3.0 entry is left exactly as it was (meta line and item)" \
  eval '[ "$(grep "^openai	" "$STORE/meta")" = "$V1_LINE" ] && [ "$(cat "$T/state/keychain/ade-secrets/openai" "$T/state/keychain/ade-secrets/openai.acl" | cksum)" = "$V1_SUM" ]'
helper_get openai
check "scope_list_and_vault: ... and get still serves it" eval '[ "$RC" = 0 ] && [ "$OUT" = fixture-value-sl-1 ]'
check "scope_list_and_vault: nothing leaked" eval 'no_leak fixture-value-sl-2 && no_leak fixture-value-sl-5'
t_done
