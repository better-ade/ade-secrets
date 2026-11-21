#!/bin/bash
# Review fixes (S1): what the docs promise about reach. docs/claude-settings.json ships the Claude Code rules that keep
# an agent away from the stores directly; docs/contract.md says plainly that helper entries are readable by Claude
# Code and anything it runs, lists every remaining route under "Residual risk", and the checks only a real Keychain
# can confirm under "Owner check". The stories no longer claim that get refuses a Bash-tool context.
. "$(dirname "$0")/lib.sh"
S="$ROOT/docs/claude-settings.json" C="$ROOT/docs/contract.md" S1="$ROOT/docs/stories/S1-local-only-store.md"
rules() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print("\n".join(d["permissions"][sys.argv[2]]))' "$S" "$1" 2>/dev/null; }
check "docs/claude-settings.json is valid JSON with permissions" eval 'rules deny >/dev/null'
for r in 'Read(~/.ade-secrets/**)' 'Bash(security find-generic-password*)' 'Bash(security dump-keychain*)' \
         'Bash(pass show*)' 'Bash(pbpaste*)'; do
  check "settings deny $r" eval 'rules deny | grep -q -x -F -- "$r"'
done
check "settings ask before Bash(ade-secrets *)" eval 'rules ask | grep -q -x -F -- "Bash(ade-secrets *)"'
check "the contract describes docs/claude-settings.json" grep -q 'docs/claude-settings.json' "$C"
check "the contract says helper entries are readable by Claude Code and anything it runs" grep -q 'readable by Claude Code and anything it runs' "$C"
check "the contract has a Residual risk section" grep -q '^#* *Residual risk' "$C"
check "the contract has an Owner check section with commands" eval 'sed -n "/^#* *Owner check/,\$p" "$C" | grep -q "security "'
check "S1 no longer claims get refuses a Bash-tool context" eval '! grep -q -i "refuses from a Bash-tool" "$S1" && ! grep -q "it refuses when called from a Bash tool context" "$S1"'
check "S1 AC4 names the helper allow-list" eval 'grep "^| 4 |" "$S1" | grep -q -- "--helper"'
t_done
