#!/bin/bash
# The start-up check (docs/contract.md, "Start-up"): an exported function, BASH_ENV, ENV, SHELLOPTS or BASHOPTS in the
# environment is refused (exit 3, a clear line naming them, no value read), whichever way the script is started:
# through its shebang (bash -p), or as `bash ade-secrets`, also with SHELLOPTS=privileged, which turns -p on after
# bash has already imported the functions. Both the macOS bash 3.2 and the bash running the tests are tried.
. "$(dirname "$0")/lib.sh"

t_setup; STORE_KIND=keychain CLIP_KIND=xclip
t_set alpha 'fixture-value-start-1'
check "a clean environment stores a value" [ "$RC" = 0 ]
LEAKF="BASH_FUNC_printf%%=() { builtin printf '%s' \"\$*\" >> $T/leak.func; builtin printf \"\$@\"; }"
for sh in /bin/bash "$BASH"; do
  v="${sh##*/}-$("$sh" -c 'echo ${BASH_VERSINFO[0]}')"
  # the reported path: `bash ade-secrets` with SHELLOPTS=privileged and an exported function
  rm -f "$T/leak.func"; clip_put ''
  EXTRA_ENV=("$LEAKF" SHELLOPTS=privileged)
  t_tty -- "$sh" "$BIN" copy alpha --for 30
  check "$v: 'bash ade-secrets' with SHELLOPTS=privileged and an exported function is refused" eval '[ "$RC" = 3 ] && has "$OUT" "BASH_FUNC_printf%%"'
  check "$v: ... and the function never sees the value" eval '! grep -q -F fixture-value-start-1 "$T/leak.func" 2>/dev/null && [ -z "$(clip)" ]'
  for bad in "$LEAKF" "BASH_ENV=$T/input/none" "ENV=$T/input/none" SHELLOPTS=xtrace BASHOPTS=extglob; do
    EXTRA_ENV=("$bad"); n="${bad%%=*}"
    t_tty -- "$sh" "$BIN" list
    check "$v: started as 'bash ade-secrets', $n in the environment is refused" eval '[ "$RC" = 3 ] && has "$OUT" "$n"'
    t_tty -- @ list
    check "$v: through the shebang (bash -p), $n in the environment is refused (children would get it)" eval '[ "$RC" = 3 ] && has "$OUT" "$n"'
  done
done
EXTRA_ENV=("$LEAKF")
t_notty -- @ get alpha
check "get refuses with an exported function too" eval '[ "$RC" = 3 ] && [ -z "$OUT" ] && has "$ERR" "BASH_FUNC_printf%%"'
EXTRA_ENV=()
t_tty -- /bin/bash "$BIN" list --names
check "started as 'bash ade-secrets' in a clean environment, it starts again as bash -p and works" eval '[ "$RC" = 0 ] && [ "$OUT" = alpha ]'
check "the restart cannot loop: it happens only without -p, and bash -p always has it" eval '[ "$(grep -c "exec /bin/bash -p" "$BIN")" = 1 ]'
t_done
