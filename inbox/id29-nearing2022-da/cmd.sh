#!/bin/bash
# ID29 seq=172: recover the immutable full payload from the successful seq=171 partial numerical audit.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
AUDIT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq171.json"

test -f "$AUDIT"
test "$(sha256sum "$AUDIT" | awk '{print $1}')" = "672a679fe8a32fa30e7d4001fe0cb6e73a889d988171295745c60217aa5a64a1"

sha256sum "$AUDIT"
wc -c "$AUDIT"
printf '%s\n' '=== BEGIN PARTIAL NUMERICAL AUDIT SEQ171 JSON ==='
cat "$AUDIT"
printf '%s\n' '=== END PARTIAL NUMERICAL AUDIT SEQ171 JSON ==='
printf '%s\n' 'registered_matrix_modified=false'
