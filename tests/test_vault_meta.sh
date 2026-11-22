#!/bin/bash
# 0.3.1 security fix: text in ~/.ade-secrets/meta is data, never code or a path. The vault used a rotation time from
# meta in bash arithmetic, where a subscript such as N_[$(cmd)] runs cmd inside the vault (which holds the age
# identity once unlocked); a leading zero (08) killed the vault as an invalid octal number; a name such as
# ../../../victim made the vault write and delete files outside the store; and report_left globbed a name such as /*
# when it counted entries left in another store.
. "$(dirname "$0")/lib.sh"
T_TIMEOUT=60
# row <name> <store> <rotated>: a line in meta as another program running as the user could write it
row() { printf '%s\t%s\tsecret\t-\t%s\t%s\tno\n' "$1" "$2" "$(date +%s)" "$3" >> "$STORE/meta"; }
vault_quits() { t_tty "expect q quit" "sleep 0.3" "snap $T/run/screen" "send q" -- @ vault; S="$(screen_of "$T/run/screen")"; }

# ---- a rotation time is code to bash arithmetic: only ^[1-9][0-9]{0,11}$ is used, else 0
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
t_set alpha fixture-value-vm-1
row hostile keychain "N_[\$(touch $T/pwned-n)]"
row hostile2 keychain "R_[\$(touch $T/pwned-r)]"
vault_quits
check "vault: a rotation time naming a set array with \$(...) runs nothing" eval '[ ! -e "$T/pwned-n" ] && [ ! -e "$T/pwned-r" ]'
check "vault: ... the vault still opens and quits, and shows the row" eval '[ "$RC" = 0 ] && has "$S" hostile && has "$S" alpha'
t_cleanup

t_setup; STORE_KIND=keychain CLIP_KIND=xclip
t_set alpha fixture-value-vm-2
row octal keychain 08
row octal2 keychain 010
vault_quits
check "vault: a rotation time 08 (not octal) does not kill the vault" eval '[ "$RC" = 0 ] && has "$S" octal && has "$S" alpha'
check "vault: ... 08 and 010 count as 0: both shown for rotation" eval 'printf "%s\n" "$S" | grep "octal " | grep -q "rotate!" && printf "%s\n" "$S" | grep "octal2" | grep -q "rotate!"'
t_cleanup
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
t_set alpha fixture-value-vm-2
row old-key keychain $(( $(date +%s) - 100 * 86400 ))
for d in 08 010 0 -1 abc 99999999999999; do
  EXTRA_ENV=("ADE_SECRETS_ROTATE_DAYS=$d"); vault_quits
  check "vault: ADE_SECRETS_ROTATE_DAYS=$d falls back to 90" eval '[ "$RC" = 0 ] && has "$S" "past 90 days"'
done
EXTRA_ENV=("ADE_SECRETS_ROTATE_DAYS=30"); vault_quits
check "vault: ADE_SECRETS_ROTATE_DAYS=30 is used" eval '[ "$RC" = 0 ] && has "$S" "past 30 days"'
EXTRA_ENV=()
t_cleanup

# ---- a name is never a path: rows whose name breaks the name rule are not loaded
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
mkdir -p -m 700 "$STORE"; : > "$STORE/meta"; chmod 600 "$STORE/meta"; echo keychain > "$STORE/store"
row ../../../victim keychain "$(date +%s)"
echo keep > "$T/home/victim-del"; row ../../../victim-del keychain "$(date +%s)"
t_tty "expect q quit" "send n" "sleep 0.5" "send owned\n" "sleep 0.5" "send q" -- @ vault
check "vault: a note cannot be written through a ../ name" eval '[ ! -e "$T/home/victim" ] && [ ! -e "$STORE/victim" ]'
t_tty "expect q quit" "send j" "send n" "sleep 0.5" "send \n" "sleep 0.5" "send q" -- @ vault
check "vault: ... nor a file deleted through one" [ "$(cat "$T/home/victim-del" 2>/dev/null)" = keep ]
vault_quits
check "vault: such rows are not listed" eval '[ "$RC" = 0 ] && hasnt "$S" victim'
t_cleanup

# ---- report_left counts names without expanding them
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
t_set alpha fixture-value-vm-3
row '/*' pass "$(date +%s)"
t_tty -- @ status
check "report_left: a name /* in another store is one entry, not a glob" eval '[ "$RC" = 0 ] && has "$OUT" "1 entry left in pass"'
t_done
