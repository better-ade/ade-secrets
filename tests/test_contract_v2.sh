#!/bin/bash
# S3 AC9 v1_unchanged: every v1 call in docs/contract.md still behaves as its table says: the v1 contract and its test
# are byte for byte as 0.3.0 shipped them, and that test passes.
# S3 AC10 contract_v2_tables: docs/contract-v2.md's tables for the commands S3 builds (the Commands rows for set, has,
# list, list --names, list --due and --version; the has, get and others columns of "The key helper and the guards")
# are read from the document and run as written, with the exact lines the contract quotes. `run` is S4's.
. "$(dirname "$0")/lib.sh"
C2="$ROOT/docs/contract-v2.md"
sha() { python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }

# ---- AC9
check "v1_unchanged: docs/contract.md is v1 as shipped in 0.3.0" [ "$(sha "$ROOT/docs/contract.md")" = 25af1f68550dfae798c061276c1b5db41b0d2f5a65121d446ed66399ba4868ac ]
check "v1_unchanged: tests/test_contract.sh is unchanged" [ "$(sha "$TESTS_DIR/test_contract.sh")" = b73e6b8a20788ed1408d532e179ce7a126b2b1aae024116bf3924df983507563 ]
V1OUT="$(bash "$TESTS_DIR/test_contract.sh" 2>&1)"; V1RC=$?
check "v1_unchanged: the v1 contract test passes ($(printf '%s\n' "$V1OUT" | tail -1 | sed 's/^# //'))" \
  eval '[ "$V1RC" = 0 ] && ! printf "%s\n" "$V1OUT" | grep -q "^not ok"'

# ---- AC10: the tables, read from the document
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
cell() { printf '%s\n' "$1" | awk -F'|' -v i="$2" '{ c = $(i + 1); gsub(/^ +| +$/, "", c); print c }'; }
cmd_row() { grep -F "| \`ade-secrets $1" "$C2" | head -1; }
quoted() { grep -o "\`$1[^\`]*\`" "$C2" | head -1 | tr -d '`'; }
check "contract_v2_tables: docs/contract-v2.md has the Commands table" eval '[ -n "$(cmd_row "has <name>")" ]'

PRESENT=acme-ops.anthropic-api-key ABSENT=acme-ops.no-such-key NEW=acme-ops.new-key
t_set "$PRESENT" fixture-value-c2-1 --helper
t_set acme-ops.zai-api-key fixture-value-c2-2
t_set legacy fixture-value-c2-3
# two entries past the rotation age, one with the scope, so list --due has names to print
awk -F'\t' -v OFS='\t' -v t=$(( $(date +%s) - 200 * 86400 )) '$1 == "legacy" || $1 == "acme-ops.zai-api-key" { $6 = t } { print }' "$STORE/meta" > "$T/meta.new" && cat "$T/meta.new" > "$STORE/meta"
STEPS=()
# run_as <context> <args...>: RC and SO (stdout only)
run_as() {
  local ctx="$1"; shift
  case "$ctx" in
    terminal) t_tty ${STEPS[@]+"${STEPS[@]}"} -- /bin/sh -c 'o=$1; shift; "$@" > "$o"' sh "$T/run/so" @ "$@"; SO="$(cat "$T/run/so")" ;;
    service) t_notty -- @ "$@"; SO="$OUT" ;;
    agent) EXTRA_ENV=(CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=fixture); t_notty -- @claude @ "$@"; SO="$OUT"; EXTRA_ENV=() ;;
    helper) EXTRA_ENV=(CLAUDE_CODE_ENTRYPOINT=cli); t_notty -- @claude /bin/sh -c '"$@"' sh @ "$@"; SO="$OUT"; EXTRA_ENV=() ;;
  esac
}
contexts() { # the "Who may call it" cell, as contexts
  case "$1" in
    "a person's terminal") echo terminal ;;
    anyone*) echo terminal service agent helper ;;
    *) echo "unknown:$1" ;;
  esac
}
stdout_ok() { # <stdout cell> <stdout>
  case "$1" in
    nothing) [ -z "$2" ] ;;
    "a table, never a value") [ "$(printf '%s\n' "$2" | head -1 | tr -s ' ')" = "SCOPE NAME KIND USED-BY AGE USE" ] && hasnt "$2" fixture-value ;;
    "one name per line"*) printf '%s\n' "$2" | awk 'NF != 1 { exit 1 }' && hasnt "$2" fixture-value ;;
    "one line, \`X.Y.Z\`") [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ;;
    *) return 1 ;;
  esac
}
# expand <command cell>: the concrete argument lists, one per line ([--scope S] with and without; other [...] dropped)
expand() {
  local c="${1#ade-secrets }" alt=""
  case "$c" in *"(or "*")"*) alt="${c#*(or }"; alt="${alt%%)*}"; c="${c%% (or*}" ;; esac
  for form in "$c" ${alt:+"$alt"}; do
    case "$form" in
      *"[--scope S]"*) printf '%s\n' "${form/ \[--scope S\]/}" "${form/\[--scope S\]/--scope acme-ops}" ;;
      *) printf '%s\n' "$(printf '%s' "$form" | sed 's/ \[[^]]*\]//g')" ;;
    esac
  done
}

# the read-only rows: has, list, list --names, list --due, --version
for key in "has <name>" "list [--scope S]" "list --names [--scope S]" "list --due [--scope S]" "--version"; do
  row="$(cmd_row "$key")"; c="$(cell "$row" 1 | tr -d '`')"; who="$(cell "$row" 2)"; so="$(cell "$row" 3)"; ex="$(cell "$row" 4)"
  check "contract_v2_tables: the row for '$key' is in the table" [ -n "$row" ]
  while IFS= read -r form; do
    [ -n "$form" ] || continue
    for ctx in $(contexts "$who"); do
      case "$ex" in
        "0 present, 1 absent")
          set -f; run_as $ctx ${form/<name>/$PRESENT} </dev/null; set +f
          check "contract_v2_tables: '$form' ($ctx): present: 0, stdout $so" eval '[ "$RC" = 0 ] && stdout_ok "$so" "$SO"'
          set -f; run_as $ctx ${form/<name>/$ABSENT} </dev/null; set +f
          check "contract_v2_tables: '$form' ($ctx): absent: 1, stdout $so" eval '[ "$RC" = 1 ] && stdout_ok "$so" "$SO"' ;;
        0)
          set -f; run_as $ctx $form </dev/null; set +f
          check "contract_v2_tables: '$form' ($ctx): 0, stdout $so" eval '[ "$RC" = 0 ] && stdout_ok "$so" "$SO"' ;;
        *) nok "contract_v2_tables: '$form': an exit cell this test does not know: $ex" ;;
      esac
    done
  done <<EOF
$(expand "$c")
EOF
done

# "The key helper and the guards": the has, get and others columns, per caller
gt_row() { grep -F "| $1 |" "$C2" | head -1; }
col() { local h; h="$(grep -F '| Caller |' "$C2" | head -1)"; awk -F'|' -v want="$1" '{ for (i = 2; i < NF; i++) { c = $i; gsub(/^ +| +$|`/, "", c); if (c == want) print i - 1 } }' <<EOF
$h
EOF
}
for caller in "A person's terminal" "A service or job of the person's login session" "An agent session (tool, hook, MCP server, plugin)" "Claude Code's key helper"; do
  row="$(gt_row "$caller")"
  check "contract_v2_tables: the guards table has the row '$caller'" [ -n "$row" ]
  case "$caller" in "A person's"*) ctx=terminal ;; "A service"*) ctx=service ;; "An agent"*) ctx=agent ;; *) ctx=helper ;; esac
  y_has="$(cell "$row" "$(col has)")" y_get="$(cell "$row" "$(col get)")" y_oth="$(cell "$row" "$(col others)")"
  run_as $ctx has "$PRESENT"
  check "contract_v2_tables: $ctx: has says '$y_has'" eval '{ [ "$y_has" = yes ] && [ "$RC" = 0 ]; } || { [ "$y_has" = no ] && [ "$RC" = 3 ]; }'
  run_as $ctx get "$PRESENT"
  check "contract_v2_tables: $ctx: get says '$y_get'" eval '{ [ "$y_get" = yes ] && [ "$RC" = 0 ] && [ "$SO" = fixture-value-c2-1 ]; } || { [ "$y_get" = no ] && [ "$RC" = 3 ] && hasnt "$SO" fixture-value; }'
  for other in "list --names" "list --due" "status"; do
    set -f; run_as $ctx $other; set +f
    check "contract_v2_tables: $ctx: $other (others) says '$y_oth'" eval '{ [ "$y_oth" = yes ] && [ "$RC" = 0 ]; } || { [ "$y_oth" = no ] && [ "$RC" = 3 ]; }'
  done
done
# set: a person's terminal, nothing on stdout; 0 stored, 1 not stored or not replaced
row="$(cmd_row "set <name>")"; who="$(cell "$row" 2)"; so="$(cell "$row" 3)"; ex="$(cell "$row" 4)"
check "contract_v2_tables: the set row reads as built" eval '[ "$who" = "a person'"'"'s terminal" ] && [ "$ex" = "0 stored, 1 not stored or not replaced" ]'
STEPS=("expect value for $NEW" "sleep 0.2" "send fixture-value-c2-4\n"); run_as terminal set "$NEW" --kind api-key --used-by hub:acme-ops --helper
check "contract_v2_tables: set <new name> --kind --used-by --helper: 0 stored, stdout $so" eval '[ "$RC" = 0 ] && stdout_ok "$so" "$SO" && t_exists "$NEW"'
STEPS=("expect value for acme-ops.plain-key" "sleep 0.2" "send fixture-value-c2-5\n"); run_as terminal set acme-ops.plain-key --plain
check "contract_v2_tables: set <name> --plain: 0 stored, not marked for the helper" eval '[ "$RC" = 0 ] && [ "$(grep "^acme-ops.plain-key	" "$STORE/meta" | cut -f 7)" = no ]'
STEPS=("expect value for acme-ops.empty" "sleep 0.2" "send \n"); run_as terminal set acme-ops.empty
check "contract_v2_tables: set with no value: 1 not stored, stdout $so" eval '[ "$RC" = 1 ] && stdout_ok "$so" "$SO" && ! t_exists acme-ops.empty'
ASK="$(quoted 'replace ')" KEPT="$(quoted 'kept ')"
check "contract_v2_tables: the contract quotes the replace question and its answer" eval '[ -n "$ASK" ] && [ -n "$KEPT" ]'
EX_NAME="${KEPT#kept }"; EX_NAME="${EX_NAME% unchanged}"
t_set "$EX_NAME" fixture-value-c2-6
awk -F'\t' -v OFS='\t' -v t=$(( $(date +%s) - 12 * 86400 - 60 )) '$1 == n { $6 = t } { print }' n="$EX_NAME" "$STORE/meta" > "$T/meta.new" && cat "$T/meta.new" > "$STORE/meta"
STEPS=("expect replace" "sleep 0.1" "send n\n"); run_as terminal set "$EX_NAME"
check "contract_v2_tables: set on an existing name asks exactly '$ASK'" eval 'printf "%s" "$OUT" | grep -q -F -- "$ASK"'
check "contract_v2_tables: ... and n is 1 not replaced, with '$KEPT', stdout $so" eval '[ "$RC" = 1 ] && has "$OUT" "$KEPT" && stdout_ok "$so" "$SO"'
STEPS=()
HAS_LINE="$(quoted 'meta lists ')"
t_set acme-ops.gone-key fixture-value-c2-7
rm -f "$T/state/keychain/ade-secrets/acme-ops.gone-key" "$T/state/keychain/ade-secrets/acme-ops.gone-key.acl"
t_notty -- @ has acme-ops.gone-key
want="${HAS_LINE//<name>/acme-ops.gone-key}"; want="${want//<store>/keychain}"
check "contract_v2_tables: has: meta without an item is 1 with '$HAS_LINE'" eval '[ "$RC" = 1 ] && has "$ERR" "$want"'
HEADER="$(grep -o 'shows `SCOPE[^`]*`' "$C2" | head -1 | sed 's/^shows `//; s/`$//')"
check "contract_v2_tables: the list header the contract names is the one list prints" [ "$HEADER" = "SCOPE NAME KIND USED-BY AGE USE" ]

check "contract_v2_tables: nothing leaked" eval 'no_leak fixture-value-c2-2 && no_leak fixture-value-c2-6'
t_done
