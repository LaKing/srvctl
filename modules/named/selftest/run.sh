#!/bin/bash
# modules/named/selftest/run.sh — run all named selftests without live BIND.

here="$(cd "$(dirname "$0")" && pwd)"
fail=0

for testfile in "$here"/*.test.mjs
do
    [[ -f $testfile ]] || continue
    echo "== $(basename "$testfile") =="
    if ! node "$testfile"
    then
        fail=1
    fi
done

for testfile in "$here"/*.test.sh
do
    [[ -f $testfile ]] || continue
    echo "== $(basename "$testfile") =="
    if ! bash "$testfile"
    then
        fail=1
    fi
done

if [[ $fail == 0 ]]
then
    echo "ALL NAMED SELFTESTS PASSED"
else
    echo "NAMED SELFTESTS FAILED" >&2
fi

exit "$fail"
