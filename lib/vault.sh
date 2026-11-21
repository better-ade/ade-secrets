# lib/vault.sh: `ade-secrets vault`, the full-screen terminal vault (story S2). Bash 3.2.
# Sourced by bin/ade-secrets after its local-only guard and store choice. Every value goes through S1's paths
# (read_hidden, clip_get, put_value, get_value, clip_put): stdin and pipes only. The screen shows names, kinds,
# used-by, rotation age, notes and messages, never a value, except the opt-in timed reveal (ADE_SECRETS_REVEAL=on,
# confirmed each time, cleared after 10 s).

ROTATE_DAYS="${ADE_SECRETS_ROTATE_DAYS:-90}"
case "$ROTATE_DAYS" in ''|*[!0-9]*) ROTATE_DAYS=90 ;; esac
{ [ "$ROTATE_DAYS" -ge 1 ] && [ "$ROTATE_DAYS" -le 3650 ]; } || ROTATE_DAYS=90
REVEAL="${ADE_SECRETS_REVEAL:-off}"
REVEAL_SECONDS=10
NOTES_DIR="$HOME_DIR/notes/$STORE"     # notes are plain text: never a secret
LIVE_DIR="$HOME_DIR/tests/$STORE"      # the live test per entry: a command that gets the value on stdin
LIVE_TIMEOUT=30
ESC=$(printf '\033')
SEL=0 FILTER="" MSG="" OVERDUE="" KEY="" FROM=""
N_=() K_=() U_=() R_=()

# ---------------------------------------------------------------- data
v_load() {
  N_=() K_=() U_=() R_=(); OVERDUE=""
  local n s k u c r h hay f limit now
  now="$(date +%s)"; limit=$((ROTATE_DAYS * 86400))
  f="$(printf '%s' "$FILTER" | tr 'A-Z' 'a-z')"
  [ -f "$META" ] || return 0
  while IFS="$(printf '\t')" read -r n s k u c r h; do
    [ -n "$n" ] || continue
    [ $((now - r)) -ge "$limit" ] && OVERDUE="$OVERDUE $n"
    if [ -n "$f" ]; then
      hay="$(printf '%s %s %s' "$n" "$k" "$u" | tr 'A-Z' 'a-z')"
      case "$hay" in *"$f"*) ;; *) continue ;; esac
    fi
    N_[${#N_[@]}]="$n"; K_[${#K_[@]}]="$k"; U_[${#U_[@]}]="$u"; R_[${#R_[@]}]="$r"
  done <<EOF
$(awk -F'\t' -v s="$STORE" '$2 == s' "$META" | sort)
EOF
  OVERDUE="${OVERDUE# }"
  [ "$SEL" -lt "${#N_[@]}" ] || SEL=$((${#N_[@]} - 1))
  [ "$SEL" -ge 0 ] || SEL=0
}
v_cur() { [ "${#N_[@]}" -gt 0 ] && printf '%s' "${N_[$SEL]}"; }
v_age() {
  local d=$(($(date +%s) - $1))
  if [ $d -ge 86400 ]; then echo "$((d / 86400))d"; elif [ $d -ge 3600 ]; then echo "$((d / 3600))h"
  elif [ $d -ge 60 ]; then echo "$((d / 60))m"; else echo now; fi
}

# ---------------------------------------------------------------- screen
v_draw() {
  local i mark flag n cur lock="" limit now
  now="$(date +%s)"; limit=$((ROTATE_DAYS * 86400))
  if [ "$STORE" = age ]; then if session_open; then lock=" - unlocked"; else lock=" - locked"; fi; fi
  {
    printf '\033[H\033[2J'
    printf 'ade-secrets vault - %s store - %s entries%s\n' "$STORE" "${#N_[@]}" "$lock"
    if [ -n "$OVERDUE" ]; then
      set -f; set -- $OVERDUE; set +f
      printf 'rotate: %s past %s days: %s\n' "$# $( [ $# = 1 ] && echo key || echo keys)" "$ROTATE_DAYS" "$OVERDUE"
    fi
    [ -n "$FILTER" ] && printf 'search: %s\n' "$FILTER"
    printf '\n  %-24s %-12s %-16s %-8s\n' NAME KIND USED-BY ROTATED
    i=0
    while [ $i -lt ${#N_[@]} ]; do
      mark="  "; [ $i = "$SEL" ] && mark="> "
      flag=""; [ $((now - R_[i])) -ge "$limit" ] && flag="rotate!"
      printf '%s%-24s %-12s %-16s %-8s %s\n' "$mark" "${N_[$i]}" "${K_[$i]}" "${U_[$i]}" "$(v_age "${R_[$i]}")" "$flag"
      i=$((i + 1))
    done
    [ ${#N_[@]} -gt 0 ] || printf '  (no entries%s; a adds one)\n' "$( [ -n "$FILTER" ] && echo ' match')"
    cur="$(v_cur)"
    if [ -n "$cur" ]; then
      printf '\nnote: %s\n' "$(cat "$NOTES_DIR/$cur" 2>/dev/null || echo -)"
      printf 'live test: %s\n' "$( [ -s "$LIVE_DIR/$cur" ] && echo set || echo 'none (t sets one)')"
    fi
    printf '\nenter copy  a add  r rotate  t test  n note  d delete  v reveal  / search  l lock  u unlock  q quit\n'
    [ -n "$MSG" ] && printf '%s\n' "$MSG"
  } >/dev/tty
}

# v_act <function> [args]: run an action in a subshell, so a refusal or an error ends the action, not the vault;
# its last message (stderr, never a value) becomes the status line
v_act() {
  local m
  m="$( ( "$@" ) 2>&1 >/dev/tty )"
  m="${m##*$'\n'}"; MSG="${m#"$ME: "}"
}
v_key() { printf '%s' "$1" >/dev/tty; KEY=""; IFS= read -rsn1 KEY </dev/tty; printf '%s\n' "$KEY" >/dev/tty; }
need_cur() { [ -n "${1:-}" ] || die 1 "no entry selected"; }

# v_value <name>: VAL from the hidden prompt, the clipboard or a generator
v_value() {
  v_key "value from (p)rompt, (c)lipboard or (g)enerate: "
  FROM="$KEY"
  case "$KEY" in
    p) read_hidden "value for $1 (hidden): " || die 1 "no value read" ;;
    c) clip_need; VAL="$(clip_get)" ;;
    g) VAL="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')" ;;
    *) die 1 "cancelled" ;;
  esac
  [ -n "$VAL" ] || die 1 "empty; nothing stored"
  case "$VAL" in *$'\n'*|*$'\r'*) die 1 "a value is one line; nothing stored" ;; esac
}
# live_test <command>: the value on stdin; its output never reaches the screen; at most LIVE_TIMEOUT seconds
live_test() {
  local pid w rc
  sh -c "$1" <&0 >/dev/null 2>&1 &
  pid=$!
  ( sleep "$LIVE_TIMEOUT"; kill "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
  w=$!
  wait "$pid"; rc=$?
  kill "$w" 2>/dev/null
  return $rc
}

# ---------------------------------------------------------------- actions (each runs in v_act's subshell)
va_add() {
  local name kind used now
  read_line "name: " || die 1 "cancelled"; name="$REPLY"; valid_name "$name"
  meta_line "$name" "$STORE" >/dev/null && die 1 "$name exists; r rotates it"
  read_line "kind [secret]: " || die 1 "cancelled"; kind="${REPLY:-secret}"; valid_label "$kind"
  read_line "used by [-]: " || die 1 "cancelled"; used="${REPLY:--}"; valid_label "$used"
  need_open
  v_value "$name"
  put_value "$name" || die 1 "could not store $name in the $STORE store"
  VAL=""
  [ "$FROM" = c ] && clip_clear
  now="$(date +%s)"; meta_put "$name" "$STORE" "$kind" "$used" "$now" "$now" no; record_store
  say "stored $name in the $STORE store$( [ "$FROM" = c ] && echo '; the clipboard is cleared')"
}

va_rotate() {
  local name="${1:-}" line tested=""; need_cur "$name"; known "$name"; need_open
  printf 'rotate %s: ' "$name" >/dev/tty
  v_value "$name"
  if [ -s "$LIVE_DIR/$name" ]; then
    printf 'testing the new value with the live test for %s ...\n' "$name" >/dev/tty
    printf '%s' "$VAL" | live_test "$(cat "$LIVE_DIR/$name")" || die 1 "the new value failed the live test for $name; the old value is kept"
    tested=1
  else
    v_key "$name has no live test (t sets one); store the new value untested? (y/N) "
    [ "$KEY" = y ] || die 1 "not rotated; the old value is kept"
  fi
  put_value "$name" || die 1 "could not store the new value for $name"
  VAL=""
  [ "$FROM" = c ] && clip_clear
  line="$(meta_line "$name" "$STORE")"
  meta_put "$name" "$STORE" "$(meta_field "$line" 3)" "$(meta_field "$line" 4)" "$(meta_field "$line" 5)" "$(date +%s)" "$(meta_field "$line" 7)"
  say "rotated $name: $( [ -n "$tested" ] && echo 'the new value passed its live test' || echo 'the new value is stored, untested')"
}

va_test() {
  local name="${1:-}"; need_cur "$name"; known "$name"
  read_line "live test for $name (a command; it gets the value on stdin, exit 0 = it works; never put a key in it; empty removes it): " || die 1 "cancelled"
  mkdir -p "$LIVE_DIR"
  if [ -z "$REPLY" ]; then rm -f "$LIVE_DIR/$name"; say "live test removed for $name"
  else printf '%s\n' "$REPLY" > "$LIVE_DIR/$name"; say "live test saved for $name"; fi
}

va_note() {
  local name="${1:-}"; need_cur "$name"; known "$name"
  read_line "note for $name (not encrypted; never a secret; empty removes it): " || die 1 "cancelled"
  case "$REPLY" in *"$(printf '\t')"*) die 1 "a note is one line of text" ;; esac
  mkdir -p "$NOTES_DIR"
  if [ -z "$REPLY" ]; then rm -f "$NOTES_DIR/$name"; say "note removed for $name"
  else printf '%s\n' "$REPLY" > "$NOTES_DIR/$name"; say "note saved for $name"; fi
}

va_forget() { need_cur "${1:-}"; cmd_forget "$1"; }
va_copy() { need_cur "${1:-}"; cmd_copy "$1"; }

# the opt-in timed reveal: off unless ADE_SECRETS_REVEAL=on, confirmed every time, cleared after 10 s (or a key)
va_reveal() {
  local name="${1:-}"; need_cur "$name"; known "$name"
  [ "$REVEAL" = on ] || die 1 "reveal is off (ADE_SECRETS_REVEAL=on enables it)"
  need_open
  v_key "show the value of $name on screen for $REVEAL_SECONDS s? (y/N) "
  [ "$KEY" = y ] || die 1 "not shown"
  VAL="$(get_value "$name")" || die 1 "could not read $name"
  printf '\033[H\033[2J\033[3J%s (hidden in %s s, or press a key):\n\n  %s\n' "$name" "$REVEAL_SECONDS" "$VAL" >/dev/tty
  VAL=""
  IFS= read -rsn1 -t "$REVEAL_SECONDS" KEY </dev/tty
  printf '\033[H\033[2J\033[3J' >/dev/tty
  say "hidden again"
}

v_search() {
  read_line "search: " || return 0
  FILTER="$REPLY"; SEL=0; MSG=""
}

# ---------------------------------------------------------------- the loop
V_STTY=""
v_restore() {
  [ -n "$V_STTY" ] && stty "$V_STTY" </dev/tty 2>/dev/null
  printf '\033[?1049l' >/dev/tty 2>/dev/null
}
cmd_vault() {
  [ $# -eq 0 ] || die 2 "usage: ade-secrets vault"
  local rest cur
  V_STTY="$(stty -g </dev/tty)" || die 1 "cannot use this terminal"
  trap v_restore EXIT
  trap 'exit 130' INT TERM HUP
  printf '\033[?1049h' >/dev/tty
  stty -echo </dev/tty
  MSG="$(report_left 2>&1 | head -1)"; MSG="${MSG#"$ME: "}"
  while :; do
    v_load; v_draw
    KEY=""; IFS= read -rsn1 KEY </dev/tty || break
    cur="$(v_cur)"
    case "$KEY" in
      "$ESC") rest=""; IFS= read -rsn2 -t 1 rest </dev/tty
        case "$rest" in "[A"|OA) [ "$SEL" -gt 0 ] && SEL=$((SEL - 1)) ;; "[B"|OB) SEL=$((SEL + 1)) ;; esac ;;
      k) [ "$SEL" -gt 0 ] && SEL=$((SEL - 1)) ;;
      j) SEL=$((SEL + 1)) ;;
      "") v_act va_copy "$cur" ;;
      a) v_act va_add ;;
      r) v_act va_rotate "$cur" ;;
      t) v_act va_test "$cur" ;;
      n) v_act va_note "$cur" ;;
      d) v_act va_forget "$cur" ;;
      v) v_act va_reveal "$cur" ;;
      /) v_search ;;
      l) v_act cmd_lock ;;
      u) v_act cmd_unlock ;;
      q) break ;;
      *) MSG="" ;;
    esac
  done
  return 0
}
