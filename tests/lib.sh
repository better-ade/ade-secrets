# tests/lib.sh: sourced by every tests/test_*.sh. Bash 3.2 compatible.
# Each test gets its own temp folder (removed by an EXIT trap), a hermetic PATH (the fakes plus an allowlist of system
# tools, so the real Keychain, pass, age and clipboard are never reachable) and a clean environment, and runs
# ade-secrets detached from the caller's process tree (tests/pty_run.py), so the session running the tests is never
# an ancestor of the command under test.
set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
BIN="$ROOT/bin/ade-secrets"
T_PASS=0 T_FAIL=0 T_NAME="$(basename "$0" .sh)"
EXTRA_ENV=()
SYS_TOOLS="bash sh env ps sed awk grep cat mv rm mkdir rmdir chmod touch date stat sleep tr cut head tail sort uniq wc
 ls find mktemp dirname basename uname python3 kill id tty stty base64 cp ln readlink expr true false od printf"

t_cleanup() { [ -n "${T:-}" ] && [ -d "$T" ] && rm -rf "$T"; }

# t_setup [fake...]: a fresh temp folder; the named fakes (default: all) on PATH
t_setup() {
  T="$(mktemp -d "${TMPDIR:-/tmp}/ade-secrets-test.XXXXXX")" && T="$(cd "$T" && pwd -P)" || exit 1
  trap t_cleanup EXIT
  mkdir -p "$T/home" "$T/bin" "$T/sys" "$T/state" "$T/tmp" "$T/run" "$T/input"
  local f t
  for t in $SYS_TOOLS; do f="$(command -v "$t" 2>/dev/null)" && [ -x "$f" ] && ln -s "$f" "$T/sys/$t"; done
  if [ $# -eq 0 ]; then set -- $(cd "$TESTS_DIR/fakes" && ls | grep -v '^_'); fi
  for t in "$@"; do cp "$TESTS_DIR/fakes/$t" "$T/bin/$t"; done
  cp "$TESTS_DIR/fakes/_fake.py" "$T/bin/_fake.py"
  : > "$T/state/calls.log"
  STORE="$T/home/.ade-secrets"
  T_N=0
}

# t_remove_fake <tool>: take a fake off PATH (to prove a missing tool is never replaced by another)
t_remove_fake() { rm -f "$T/bin/$1"; }

# the environment every run gets; EXTRA_ENV adds to it (e.g. EXTRA_ENV=(CLAUDECODE=1))
t_env() {
  printf '%s\n' "HOME=$T/home" "PATH=$T/bin:$T/sys" "TMPDIR=$T/tmp" "TERM=xterm" "LANG=C" "LC_ALL=C" \
    "ADE_SECRETS_HOME=$STORE" "FAKE_STATE=$T/state" "FAKE_LOG=$T/state/calls.log"
  [ -n "${STORE_KIND:-}" ] && printf '%s\n' "ADE_SECRETS_STORE=$STORE_KIND"
  [ -n "${CLIP_KIND:-}" ] && printf '%s\n' "ADE_SECRETS_CLIPBOARD=$CLIP_KIND"
  [ ${#EXTRA_ENV[@]} -gt 0 ] && printf '%s\n' "${EXTRA_ENV[@]}"
  return 0
}

_t_cmd() { # prints nothing; fills CMD with env -i <env> <args>
  CMD=(env -i)
  local line
  while IFS= read -r line; do CMD+=("$line"); done <<EOF
$(t_env)
EOF
}

# t_tty [step...] -- <command words>: run in a pty, like a user's own terminal. Steps: "expect RE", "send TEXT",
# "sleep S". Sets RC and OUT (the whole screen stream, carriage returns removed). A command word "@" stands for
# ade-secrets, "@claude" for the fake claude.
t_tty() {
  T_N=$((T_N + 1)); local steps="$T/input/steps.$T_N" out="$T/run/out.$T_N"; : > "$steps"
  while [ $# -gt 0 ] && [ "$1" != -- ]; do printf '%s\n' "$1" >> "$steps"; shift; done
  shift; _t_cmd; _t_words "$@"
  python3 "$TESTS_DIR/pty_run.py" --steps "$steps" --out "$out" --timeout "${T_TIMEOUT:-30}" -- "${CMD[@]}" 2>"$out.harness"
  RC=$?; OUT="$(tr -d '\r' < "$out" 2>/dev/null)"
}

# t_notty [--stdin FILE] -- <command words>: no terminal at all. Sets RC, OUT (stdout), ERR (stderr).
t_notty() {
  T_N=$((T_N + 1)); local in=/dev/null o="$T/run/o.$T_N" e="$T/run/e.$T_N"
  [ "$1" = --stdin ] && { in="$2"; shift 2; }
  [ "$1" = -- ] && shift
  _t_cmd; _t_words "$@"
  python3 "$TESTS_DIR/pty_run.py" --no-pty --stdin "$in" --out "$o" --err "$e" --timeout "${T_TIMEOUT:-30}" -- "${CMD[@]}"
  RC=$?; OUT="$(cat "$o")"; ERR="$(cat "$e")"
}

_t_words() { local w; for w in "$@"; do case "$w" in @) CMD+=("$BIN") ;; @claude) CMD+=("$T/bin/claude") ;; *) CMD+=("$w") ;; esac; done; }

# the age store asks for its passphrase on every set and copy (it keeps no session)
AGE_PW='fixture-pass-phrase'
_t_pw() { if [ "${STORE_KIND:-}" = age ]; then PW_STEPS=("expect Enter passphrase" "sleep 0.1" "send $AGE_PW\n"); else PW_STEPS=(); fi; }
# t_set <name> <value> [set options...]: store a value through the hidden prompt
t_set() {
  local n="$1" v="${2//\\/\\\\}"; shift 2; _t_pw
  t_tty ${PW_STEPS[@]+"${PW_STEPS[@]}"} "expect value for $n" "sleep 0.2" "send $v\n" -- @ set "$n" ${1+"$@"}
}
# t_copy <name> [copy options...]: copy, answering the age passphrase prompt when there is one
t_copy() { _t_pw; t_tty ${PW_STEPS[@]+"${PW_STEPS[@]}"} -- @ copy "$@"; }
# t_unlock [passphrase]: create the age store (choose a passphrase), or check the passphrase of an existing one
t_unlock() {
  local p="${1:-$AGE_PW}"
  if [ -f "$STORE/age/identity.age" ]; then t_tty "expect Enter passphrase" "sleep 0.1" "send $p\n" -- @ unlock
  else t_tty "expect Enter passphrase" "sleep 0.1" "send $p\n" "expect Confirm" "sleep 0.1" "send $p\n" -- @ unlock; fi
}
clip() { cat "$T/state/clipboard" 2>/dev/null; }
clip_put() { printf '%s' "$1" > "$T/state/clipboard"; }
calls() { cat "$T/state/calls.log"; }

ok() { T_PASS=$((T_PASS + 1)); echo "ok - $T_NAME: $1"; }
nok() { T_FAIL=$((T_FAIL + 1)); echo "not ok - $T_NAME: $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/    # /' | head -20; return 0; }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else nok "$d" "rc=${RC:-} out=${OUT:-} err=${ERR:-}"; fi; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
hasnt() { ! has "$1" "$2"; }
# no_leak <value>: the value is in no logged argv or environment, no screen, and no file outside the fake stores
# ($T/input holds what the test itself typed)
no_leak() {
  local v="$1" hits
  grep -F -q -- "$v" "$T/state/calls.log" && return 1
  hits="$(grep -r -l -F -- "$v" "$T" 2>/dev/null | grep -v -e "^$T/state/" -e "^$T/input/" || true)"
  [ -z "$hits" ] || { echo "    # leaked into: $hits"; return 1; }
}
t_done() { echo "# $T_NAME: $T_PASS passed, $T_FAIL failed"; [ "$T_FAIL" -eq 0 ]; }
