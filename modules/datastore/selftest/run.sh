#!/bin/bash
#
# modules/datastore/selftest/run.sh — run every datastore selftest, aggregate
# exit codes. Usage:  bash modules/datastore/selftest/run.sh
# Returns non-zero if any test file fails (usable as a verify/CI gate).

here="$(cd "$(dirname "$0")" && pwd)"
fail=0

for t in "$here"/*.test.sh
do
    [[ -f "$t" ]] || continue
    echo "== $(basename "$t") =="
    if ! bash "$t"
    then
        fail=1
    fi
done

for t in "$here"/*.test.mjs
do
    [[ -f "$t" ]] || continue
    echo "== $(basename "$t") =="
    if ! node "$t"
    then
        fail=1
    fi
done

if [[ $fail == 0 ]]
then
    echo "ALL DATASTORE SELFTESTS PASSED"
else
    echo "DATASTORE SELFTESTS FAILED" >&2
fi
exit $fail
