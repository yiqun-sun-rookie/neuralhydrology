#!/bin/bash
set -eo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
B01_RECORD="$TARGET/deployment/development_B01_s100_job_id_v01.txt"
D01_RECORD="$TARGET/deployment/development_D01_s100_job_id_v01.txt"
D02_RECORD="$TARGET/deployment/development_D02_s100_job_id_v01.txt"
D03_RECORD="$TARGET/deployment/development_D03_s100_job_id_v01.txt"
SELECT_RECORD="$TARGET/deployment/dense_selection_job_id_v01.txt"
M01_RECORD="$TARGET/deployment/development_M01_s100_job_id_v01.txt"

echo "=== SUBMIT STRICT SEQUENTIAL DENSE-TO-MOE CHAIN ==="
date -Is
hostname
cd "$ROOT"

B01_SUBMISSION=$(tr -d '[:space:]' < "$B01_RECORD")
B01_JOB=$(printf '%s' "$B01_SUBMISSION" | cut -d';' -f1)
case "$B01_JOB" in
  *[!0-9]*|'') echo "Invalid B01 job record: $B01_SUBMISSION" >&2; exit 1 ;;
esac

for record in "$D01_RECORD" "$D02_RECORD" "$D03_RECORD" "$SELECT_RECORD" "$M01_RECORD"; do
  if [ -e "$record" ]; then
    echo "Refusing to overwrite existing downstream job record: $record" >&2
    cat "$record"
    exit 1
  fi
done

python - "$ROOT" "$B01_JOB" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
b01_job = sys.argv[2]
bindings_path = root / "src/modern_transformer_moe/registry/development_run_bindings.json"
bindings = json.loads(bindings_path.read_text(encoding="utf-8"))
records = bindings["records"]

b01 = [record for record in records if record["role"] == "B01" and record["seed"] == 100]
if len(b01) != 1 or b01[0]["run_id"] != f"id30_B01_s100_slurm{b01_job}" or b01[0]["status"] != "RUNNING":
    raise RuntimeError(f"B01 is not the unique live upstream run: {b01}")

unexpected = [record for record in records if record["role"] in {"D01", "D02", "D03", "M01"} and record["seed"] == 100]
if unexpected:
    raise RuntimeError(f"Downstream seed-100 bindings already exist: {unexpected}")

invocation_root = root / "results/30_modern_transformer_moe/_development_invocations"
existing = []
if invocation_root.exists():
    for role in ("D01", "D02", "D03", "M01"):
        existing.extend(invocation_root.glob(f"id30_{role}_s100_slurm*"))
if existing:
    raise RuntimeError(f"Downstream seed-100 invocation directories already exist: {sorted(existing)}")

for path in (
    root / "results/30_modern_transformer_moe/dense_selection_report.json",
    root / "results/30_modern_transformer_moe/single_seed_dense_gate.json",
    root / "src/modern_transformer_moe/configs/moe_selected_s100.yml",
):
    if path.exists():
        raise RuntimeError(f"Post-dense artifact exists before dense runs complete: {path}")

print(json.dumps({
    "b01_job_id": b01_job,
    "b01_status": b01[0]["status"],
    "downstream_bindings": 0,
    "downstream_invocations": 0,
    "post_dense_artifacts": 0,
}, sort_keys=True))
PY

B01_STATE=$(squeue -h -j "$B01_JOB" -o '%T')
if [ "$B01_STATE" != "RUNNING" ]; then
  echo "B01 must be RUNNING before the dependency chain is created; state=$B01_STATE" >&2
  exit 1
fi

submit_and_record() {
  local dependency=$1
  local record=$2
  shift 2
  local submission
  local job_id
  submission=$(sbatch --partition=hgpu2 --nodelist=ngu009 --dependency="afterok:${dependency}" --parsable "$@")
  job_id=$(printf '%s' "$submission" | cut -d';' -f1)
  case "$job_id" in
    *[!0-9]*|'') echo "Unexpected sbatch response: $submission" >&2; exit 1 ;;
  esac
  umask 077
  printf '%s\n' "$submission" > "$record.tmp"
  mv "$record.tmp" "$record"
  printf '%s\n' "$job_id"
}

D01_JOB=$(submit_and_record "$B01_JOB" "$D01_RECORD" \
  src/modern_transformer_moe/hpc/submit_seed100_development.slurm 215269 D01)
D02_JOB=$(submit_and_record "$D01_JOB" "$D02_RECORD" \
  src/modern_transformer_moe/hpc/submit_seed100_development.slurm 215269 D02)
D03_JOB=$(submit_and_record "$D02_JOB" "$D03_RECORD" \
  src/modern_transformer_moe/hpc/submit_seed100_development.slurm 215269 D03)
SELECT_JOB=$(submit_and_record "$D03_JOB" "$SELECT_RECORD" \
  src/modern_transformer_moe/hpc/submit_dense_selection.slurm)
M01_JOB=$(submit_and_record "$SELECT_JOB" "$M01_RECORD" \
  src/modern_transformer_moe/hpc/submit_m01_development.slurm)

echo "B01=$B01_JOB"
echo "D01=$D01_JOB dependency=afterok:$B01_JOB"
echo "D02=$D02_JOB dependency=afterok:$D01_JOB"
echo "D03=$D03_JOB dependency=afterok:$D02_JOB"
echo "SELECT=$SELECT_JOB dependency=afterok:$D03_JOB"
echo "M01=$M01_JOB dependency=afterok:$SELECT_JOB"
squeue -j "$B01_JOB,$D01_JOB,$D02_JOB,$D03_JOB,$SELECT_JOB,$M01_JOB" \
  -o '%.18i %.12P %.28j %.8T %.10M %.30R'
for job_id in "$D01_JOB" "$D02_JOB" "$D03_JOB" "$SELECT_JOB" "$M01_JOB"; do
  scontrol show job -o "$job_id" | sed -n 's/.*JobId=\([^ ]*\).*JobState=\([^ ]*\).*Dependency=\([^ ]*\).*/job_id=\1 state=\2 dependency=\3/p'
done
date -Is
