#!/bin/bash
# placeholder until S1: the suite runs every tests/test_*.sh
cd "$(dirname "$0")"; rc=0; for t in test_*.sh; do [ -e "$t" ] || continue; bash "$t" || rc=1; done; echo ok; exit $rc
