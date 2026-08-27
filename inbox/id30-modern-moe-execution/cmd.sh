#!/bin/bash
set -euo pipefail
umask 077

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
EXPECTED_COMMIT=e8d0131cc2cb627d8aee583510a8ceb998331aee
EXPECTED_FORCING_MANIFEST=1c1a9103bb4c44ce7473aafe40193aa45439fe85948cb95432bf9b7a50d8833c
EXPECTED_SUPERVISION_MANIFEST=613620351819f106d137a8e10a551a4924e367cf37f83fcf545b4f9bdd12412e
JOB_RECORD="$TARGET/deployment/preselection_gates_job_id_v01.txt"

echo "=== VERIFY SAFE-DATA GATE ==="
date -Is
hostname
cd "$ROOT"
ACTUAL_COMMIT=$(git rev-parse HEAD)
echo "expected_commit=$EXPECTED_COMMIT"
echo "actual_commit=$ACTUAL_COMMIT"
test "$ACTUAL_COMMIT" = "$EXPECTED_COMMIT"
git diff --quiet
git diff --cached --quiet
test ! -e "$JOB_RECORD"
test "$(sha256sum src/modern_transformer_moe/registry/track0_development_forcing_manifest_v01.json | awk '{print $1}')" = "$EXPECTED_FORCING_MANIFEST"
test "$(sha256sum src/modern_transformer_moe/registry/track0_supervision_manifest_v01.json | awk '{print $1}')" = "$EXPECTED_SUPERVISION_MANIFEST"
python - <<'PY'
import json
from pathlib import Path

report = json.loads(
    Path("results/30_modern_transformer_moe/_reports/track0_bundle_audit.json").read_text(encoding="utf-8")
)
expected = {
    "status": "PASS",
    "basin_count": 531,
    "forcing_row_count": 1888767,
    "supervision_row_count": 1745928,
    "forcing_date_min": "1999-01-05",
    "forcing_date_max": "2008-09-30",
    "supervision_date_min": "1999-10-01",
    "supervision_date_max": "2008-09-30",
}
for key, value in expected.items():
    assert report.get(key) == value, (key, report.get(key), value)
print("SAFE_DATA_GATE_PASS")
PY

echo "=== SUBMIT PRESELECTION GATES ==="
mkdir -p logs/30_modern_transformer_moe
JOB_ID=$(sbatch --parsable src/modern_transformer_moe/hpc/submit_preselection_gates.slurm)
printf '%s\n' "$JOB_ID" | tee "$JOB_RECORD"
JOB_NUM=$(printf '%s' "$JOB_ID" | cut -d';' -f1)
squeue -j "$JOB_NUM" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
echo "=== COMPLETE ==="
date -Is
