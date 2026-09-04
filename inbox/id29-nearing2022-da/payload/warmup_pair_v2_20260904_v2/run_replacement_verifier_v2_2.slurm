#!/usr/bin/env bash
#SBATCH --job-name=N22-replv2b
#SBATCH --partition=hgpu4
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:30:00
#SBATCH --output=/data1/home/sunyiq/nearing2022_da/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair_v2_20260904/logs/%x_%j.out
#SBATCH --error=/data1/home/sunyiq/nearing2022_da/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair_v2_20260904/logs/%x_%j.err

set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
BASE="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair_v2_20260904"
VERIFIER="$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_pair_v2_20260904/verify_warmup_target_replacement_chain_v2.py"
SELF="$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_pair_v2_20260904/run_replacement_verifier_v2_2.slurm"
FINAL="$BASE/replacement_verification_v2"
WORK="$BASE/.replacement_verification_v2.preparing-${SLURM_JOB_ID}"
FAILED_WORK="$BASE/.replacement_verification.preparing-220487"
FAILED_ERR="$BASE/logs/N22-replv2_220487.err"
EXPECTED_VERIFIER_SHA256=0b971f3b4d98d70184b0ba4c268e61d5b7173776719c662b52eb4cb3893e7969

test ! -e "$FINAL"
test ! -e "$WORK"
test -f "$VERIFIER"
test -f "$SELF"
test -d "$FAILED_WORK"
test -f "$FAILED_ERR"
test ! -L "$VERIFIER"
test ! -L "$SELF"
test "$(sha256sum "$VERIFIER" | awk '{print $1}')" = "$EXPECTED_VERIFIER_SHA256"
grep -Fq 'Mask audit stdout does not reproduce the published audit JSON' "$FAILED_ERR"

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
  source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

SCHEDULER_ROWS=
for job in 202510 202511; do
  row=$(sacct -n -X -P -j "$job" --format=JobIDRaw,State,ExitCode,Start,End,NodeList | \
    awk -F'|' -v expected="$job" '$1 == expected {print}')
  test "$(printf '%s\n' "$row" | sed '/^$/d' | wc -l)" -eq 1
  IFS='|' read -r job_id state exit_code start end node_list <<<"$row"
  test "$job_id" = "$job"
  test "$state" = COMPLETED
  test "$exit_code" = 0:0
  test -n "$start"
  test -n "$end"
  test -n "$node_list"
  SCHEDULER_ROWS="${SCHEDULER_ROWS}${row}"$'\n'
done

mkdir "$WORK"
printf '%s' "$SCHEDULER_ROWS" > "$WORK/scheduler_rows.txt"

python - "$WORK/scheduler_rows.txt" "$WORK/scheduler_gate.json" <<'PY'
import json
import os
from pathlib import Path
import sys

rows_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
rows = []
for line in rows_path.read_text(encoding="utf-8").splitlines():
    job_id, state, exit_code, start, end, node_list = line.split("|")
    rows.append({
        "job_id": job_id,
        "state": state,
        "exit_code": exit_code,
        "start": start,
        "end": end,
        "node_list": node_list,
    })
if [row["job_id"] for row in rows] != ["202510", "202511"]:
    raise ValueError(f"Unexpected scheduler job order: {rows}")
if any(row["state"] != "COMPLETED" or row["exit_code"] != "0:0" for row in rows):
    raise ValueError(f"Replacement scheduler gate failed: {rows}")
payload = {
    "schema": "nearing2022-warmup-target-replacement-scheduler-gate-v1",
    "scheduler_gate_passed": True,
    "jobs": rows,
    "verification_job_id": os.environ["SLURM_JOB_ID"],
    "verification_node": os.environ.get("SLURMD_NODENAME"),
    "required_submission_dependency": "afterok:202511",
    "registered_matrix_modified": False,
}
output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
PY

python -u "$VERIFIER" --repo-root "$ROOT" --output "$WORK/artifact_verification_1.json" \
  > "$WORK/artifact_verification_stdout_1.json"
python -u "$VERIFIER" --repo-root "$ROOT" --output "$WORK/artifact_verification_2.json" \
  > "$WORK/artifact_verification_stdout_2.json"
cmp "$WORK/artifact_verification_1.json" "$WORK/artifact_verification_2.json"
cmp "$WORK/artifact_verification_stdout_1.json" "$WORK/artifact_verification_stdout_2.json"
cp "$VERIFIER" "$WORK/verify_warmup_target_replacement_chain_v2.py"
cp "$SELF" "$WORK/run_replacement_verifier_v2_2.slurm"

python - "$WORK" "$VERIFIER" "$SELF" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys

work = Path(sys.argv[1])
verifier = Path(sys.argv[2])
wrapper = Path(sys.argv[3])


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


scheduler = json.loads((work / "scheduler_gate.json").read_text(encoding="utf-8"))
artifact_1 = json.loads((work / "artifact_verification_1.json").read_text(encoding="utf-8"))
artifact_2 = json.loads((work / "artifact_verification_2.json").read_text(encoding="utf-8"))
if artifact_1 != artifact_2:
    raise ValueError("Independent artifact-verification payloads differ")
if not scheduler["scheduler_gate_passed"] or not artifact_1["entry_artifact_gate_passed"]:
    raise ValueError("Replacement joint gate did not pass")
if artifact_1["registered_matrix_modified"]:
    raise ValueError("Artifact receipt reports a registered-matrix modification")
joint = {
    "schema": "nearing2022-warmup-target-replacement-joint-gate-v1",
    "joint_entry_gate_passed": True,
    "scheduler_gate_sha256": digest(work / "scheduler_gate.json"),
    "artifact_verification_sha256": digest(work / "artifact_verification_1.json"),
    "artifact_reproduction_byte_identical": True,
    "verifier_sha256": digest(verifier),
    "slurm_wrapper_sha256": digest(wrapper),
    "replacement_job_ids": ["202510", "202511"],
    "verification_job_id": os.environ["SLURM_JOB_ID"],
    "supersedes_failed_verification_job_id": "220487",
    "repair_scope": "validate mask-isolation stdout against its documented conclusion-only output",
    "pair_runner_adaptation_permitted": True,
    "pair_training_submission_permitted": False,
    "registered_matrix_modified": False,
}
(work / "joint_gate.json").write_text(
    json.dumps(joint, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
)

files = []
for path in sorted(work.rglob("*"), key=lambda item: item.as_posix()):
    if path.is_symlink():
        raise ValueError(f"Verification output contains a link: {path}")
    if path.is_file() and path.name != "artifact_manifest.json":
        files.append({
            "path": path.relative_to(work).as_posix(),
            "bytes": path.stat().st_size,
            "sha256": digest(path),
        })
manifest = {
    "schema": "nearing2022-warmup-target-replacement-verification-manifest-v1",
    "file_count": len(files),
    "total_bytes": sum(item["bytes"] for item in files),
    "files": files,
}
(work / "artifact_manifest.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
)
print(json.dumps(joint, sort_keys=True))
print(json.dumps({"manifest_sha256": digest(work / "artifact_manifest.json")}, sort_keys=True))
PY

test "$(find "$WORK" -type l -print -quit)" = ""
sha256sum "$WORK"/*
mv "$WORK" "$FINAL"
scontrol show job "$SLURM_JOB_ID"
echo "final=$FINAL"
