#!/bin/bash
set -eo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
GATE_JOB_ID=215269
JOB_RECORD="$TARGET/deployment/development_B01_s100_job_id_v01.txt"
EXPECTED_REVISION=eef5ecf460775b679eabda36ca4df090c14d4e36

echo "=== B01 DEVELOPMENT SUBMISSION PREFLIGHT ==="
date -Is
hostname
cd "$ROOT"

GATE_STATE=
GATE_EXIT=
while IFS='|' read -r job_id _ state exit_code _; do
  if [ "$job_id" = "$GATE_JOB_ID" ]; then
    GATE_STATE=$state
    GATE_EXIT=$exit_code
    break
  fi
done < <(sacct -j "$GATE_JOB_ID" --format=JobIDRaw,JobName,State,ExitCode,Elapsed -n -P)
if [ "$GATE_STATE" != "COMPLETED" ] || [ "$GATE_EXIT" != "0:0" ]; then
  echo "Preselection job is not a successful terminal dependency: state=$GATE_STATE exit=$GATE_EXIT" >&2
  exit 1
fi

REVISION=$(git rev-parse HEAD)
if [ "$REVISION" != "$EXPECTED_REVISION" ]; then
  echo "Remote source revision drift: expected=$EXPECTED_REVISION actual=$REVISION" >&2
  exit 1
fi

python - "$ROOT" "$GATE_JOB_ID" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
gate_job_id = sys.argv[2]
allowed_changes = {
    "src/modern_transformer_moe/registry/track0_development_forcing_manifest_v01.json",
    "src/modern_transformer_moe/registry/track0_supervision_manifest_v01.json",
}
status_lines = subprocess.check_output(
    ["git", "status", "--porcelain=v1", "--untracked-files=no"], cwd=root, text=True
).splitlines()
changed_paths = {line[3:] for line in status_lines if line.strip()}
unexpected = sorted(changed_paths - allowed_changes)
if unexpected:
    raise RuntimeError(f"Unexpected tracked changes before B01 submission: {unexpected}")

probe_root = root / "results/30_modern_transformer_moe/_gpu_resource_probes"
for experiment_id in ("B01", "D01", "D02", "D03"):
    report_path = probe_root / f"id30_{experiment_id}_s100_slurm{gate_job_id}" / "probe_report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("status") != "COMPLETE" or report.get("overall_status") != "PASS":
        raise RuntimeError(f"Gate report is not PASS: {experiment_id}: {report}")
    if not all(report.get("checks", {}).values()):
        raise RuntimeError(f"Gate checks are not all true: {experiment_id}: {report.get('checks')}")

bindings_path = root / "src/modern_transformer_moe/registry/development_run_bindings.json"
bindings = json.loads(bindings_path.read_text(encoding="utf-8"))
duplicates = [record for record in bindings["records"] if record["role"] == "B01" and record["seed"] == 100]
if duplicates:
    raise RuntimeError(f"B01 seed 100 already has a binding: {duplicates}")

invocation_root = root / "results/30_modern_transformer_moe/_development_invocations"
existing = sorted(invocation_root.glob("id30_B01_s100_slurm*")) if invocation_root.exists() else []
if existing:
    raise RuntimeError(f"B01 seed 100 already has invocation directories: {existing}")

print(json.dumps({
    "gate_job_id": gate_job_id,
    "gate_reports": ["B01", "D01", "D02", "D03"],
    "tracked_changes": sorted(changed_paths),
    "duplicate_bindings": 0,
    "duplicate_invocations": 0,
}, sort_keys=True))
PY

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
python -m src.modern_transformer_moe.scripts.audit_configs
python -m src.modern_transformer_moe.scripts.inspect_development_runs --all

if [ -e "$JOB_RECORD" ]; then
  echo "Refusing to overwrite existing job record: $JOB_RECORD" >&2
  cat "$JOB_RECORD"
  exit 1
fi

SUBMISSION=$(sbatch --partition=hgpu2 --nodelist=ngu009 --parsable \
  src/modern_transformer_moe/hpc/submit_seed100_development.slurm "$GATE_JOB_ID" B01)
JOB_ID=$(printf '%s' "$SUBMISSION" | cut -d';' -f1)
case "$JOB_ID" in
  *[!0-9]*|'') echo "Unexpected sbatch response: $SUBMISSION" >&2; exit 1 ;;
esac
umask 077
printf '%s\n' "$SUBMISSION" > "$JOB_RECORD.tmp"
mv "$JOB_RECORD.tmp" "$JOB_RECORD"

echo "submitted_job_id=$JOB_ID"
squeue -j "$JOB_ID" -o '%.18i %.12P %.28j %.8T %.10M %.30R'
echo "job_record=$JOB_RECORD"
date -Is
