#!/bin/bash
# The verification command (docs/stories, CI): every tests/test_*.sh, macOS bash 3.2 and Linux bash 5.
# Each test file prints "ok"/"not ok" lines; this exits non-zero when any file fails.
cd "$(dirname "$0")" || exit 1
files=0 failed=0 checks=0 bad=0
for t in test_*.sh; do
  [ -e "$t" ] || continue
  files=$((files + 1))
  out="$(bash "$t" 2>&1)"; rc=$?
  printf '%s\n' "$out"
  n=$(printf '%s\n' "$out" | grep -c '^ok - ')
  m=$(printf '%s\n' "$out" | grep -c '^not ok - ')
  checks=$((checks + n + m)); bad=$((bad + m))
  if [ $rc -ne 0 ] || [ "$m" -ne 0 ]; then failed=$((failed + 1)); echo "FAIL $t (exit $rc)"; fi
done
echo "# $files test files, $checks checks, $bad failed; bash $BASH_VERSION on $(uname -s)"
[ $failed -eq 0 ] && [ $files -gt 0 ] && echo ok
[ $failed -eq 0 ] && [ $files -gt 0 ]
