#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
PROBE_JOB_ID=215878
TEMPLATE=src/hydrologic_dynamic_tokens/hpc/submit_development_experiment.slurm
PROBE_REPORT="results/31_hydrologic_dynamic_tokens/_gpu_resource_probes/slurm${PROBE_JOB_ID}/probe_report.json"
OUTDIR="results/31_hydrologic_dynamic_tokens/_submissions/slurm${PROBE_JOB_ID}"
EXPECTED_TEMPLATE_SHA=99e6b130fb2d10c0d229aa0befc3f820c5dfce4cbf431261c2d93a9a51258baa
EXPECTED_REPORT_SHA=f4dc3c7e76282f012f27e7f3a86b8cef6b3f817ce16b54f598167ef6517680c9

test -d "$ROOT/.git"
cd "$ROOT"
test -f "$TEMPLATE"
test -f "$PROBE_REPORT"
test "$(sha256sum "$TEMPLATE" | awk '{print $1}')" = "$EXPECTED_TEMPLATE_SHA"
test "$(sha256sum "$PROBE_REPORT" | awk '{print $1}')" = "$EXPECTED_REPORT_SHA"
test "$(grep -Fxc 'PROBE_JOB_ID="__PROBE_JOB_ID__"' "$TEMPLATE")" -eq 1
test "$(grep -Fxc 'EXPERIMENT_ID="__EXPERIMENT_ID__"' "$TEMPLATE")" -eq 1
test ! -e "$OUTDIR"
mkdir -p "$OUTDIR"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -m src.hydrologic_dynamic_tokens.scripts.audit_configs
python - "$PROBE_REPORT" <<'PY'
import json
import sys
from pathlib import Path

from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["probe_id"] == "slurm215878"
assert report["status"] == "PASS"
assert all(report["checks"].values())
current = capture_source_integrity("DL01")
assert report["source_integrity_before"] == current
assert report["source_integrity_after"] == current
print("BOUND_PROBE_AND_SOURCE_PASS", report["probe_id"])
PY

for EXPERIMENT_ID in DT08 DL01; do
  OUTFILE="$OUTDIR/submit_${EXPERIMENT_ID}_slurm${PROBE_JOB_ID}.slurm"
  sed \
    -e "s/__PROBE_JOB_ID__/${PROBE_JOB_ID}/" \
    -e "s/__EXPERIMENT_ID__/${EXPERIMENT_ID}/" \
    "$TEMPLATE" > "$OUTFILE"
  chmod 0644 "$OUTFILE"
  test "$(wc -l < "$OUTFILE")" -eq "$(wc -l < "$TEMPLATE")"
  test "$(sed -n '16p' "$OUTFILE")" = "PROBE_JOB_ID=\"${PROBE_JOB_ID}\""
  test "$(sed -n '17p' "$OUTFILE")" = "EXPERIMENT_ID=\"${EXPERIMENT_ID}\""
  if grep -Eq '__PROBE_JOB_ID__|__EXPERIMENT_ID__' "$OUTFILE"; then
    echo "Unresolved placeholder in $OUTFILE" >&2
    exit 1
  fi
  awk 'NR == 16 {$0 = "PROBE_JOB_ID=\"__PROBE_JOB_ID__\""} NR == 17 {$0 = "EXPERIMENT_ID=\"__EXPERIMENT_ID__\""} {print}' "$OUTFILE" | cmp -s - "$TEMPLATE"
  bash -n "$OUTFILE"
  echo "JOB_SCRIPT_SHA256 ${EXPERIMENT_ID} $(sha256sum "$OUTFILE" | awk '{print $1}') $OUTFILE"
done

for EXPERIMENT_ID in DT08 DL01; do
  OUTFILE="$OUTDIR/submit_${EXPERIMENT_ID}_slurm${PROBE_JOB_ID}.slurm"
  echo "=== SUBMIT ${EXPERIMENT_ID} ==="
  echo "sbatch $OUTFILE"
  SUBMISSION="$(sbatch "$OUTFILE")"
  echo "$SUBMISSION"
  test "$(printf '%s\n' "$SUBMISSION" | grep -Ec '^Submitted batch job [0-9]+$')" -eq 1
  JOB_ID="$(printf '%s\n' "$SUBMISSION" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')"
  test -n "$JOB_ID"
  test "$JOB_ID" != "215876"
  test "$JOB_ID" != "$PROBE_JOB_ID"
  echo "ID31_${EXPERIMENT_ID}_JOB_ID=$JOB_ID"
  squeue -j "$JOB_ID" -o '%.18i %.12P %.30j %.2t %.10M %.20R' || true
done

echo "ID31_DT08_DL01_SUBMISSION_PASS"
