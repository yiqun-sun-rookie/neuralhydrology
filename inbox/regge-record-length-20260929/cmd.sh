#!/bin/bash
set -eo pipefail
sequence=10

ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
PRIOR_STAGE="$ROOT/runtime_stage_002"
MICROMAMBA="$PRIOR_STAGE/tool/bin/micromamba"
DIAG_PREFIX="$ROOT/runtime_probe_diag_004"

test -d "$ROOT"
test -x "$MICROMAMBA"
test ! -e "$DIAG_PREFIX"
echo "=== dry-run diagnosis of exact environment solve ==="
export MAMBA_ROOT_PREFIX="$PRIOR_STAGE/mamba_root"
set +e
timeout 600 "$MICROMAMBA" create --dry-run --json -p "$DIAG_PREFIX" \
  -c pytorch -c defaults \
  python=3.11.5 numpy=1.26.4 pandas=2.3.3 pytorch=2.2.2 cpuonly \
  psutil=5.9.0 mkl=2023.1.0 intel-openmp=2023.1.0 \
  matplotlib-base=3.10.6 conda-pack pytest
solver_rc=$?
set -e
printf 'solver_exit_code=%s\n' "$solver_rc"
if [ -e "$DIAG_PREFIX" ]; then
  printf 'unexpected_diagnostic_prefix_created=yes path=%s\n' "$DIAG_PREFIX"
  find "$DIAG_PREFIX" -maxdepth 2 -type f -printf '%p %s bytes\n' | sort | head -80
  exit 1
fi
printf 'diagnostic_prefix_created=no\n'
