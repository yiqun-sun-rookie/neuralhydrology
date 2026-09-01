#!/bin/bash
# Submit exactly one package-native v2r5 allocation probe. This command does
# not acquire or install a runtime, stage data, train a model, or run formal
# evaluation.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
PROBE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/allocation_probe.slurm"
PROBE_SCRIPT_SHA=0a11351349ed45fcbc1f3d8e88d622057315d6a2f1e497d5aef06bcf8d3f11f8
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r5.json"
EXECUTION_CONFIG_SHA=5c1cdc50d28fde46b92947a1fa0fb628a177f7ad573fcea4f943d55934a04bc7
DEPLOYMENT_SUMMARY="${ROOT}/status/deployment_summary.json"
DEPLOYMENT_SUMMARY_SIZE=1178
DEPLOYMENT_SUMMARY_SHA=cb20074c651bc3cb206642c21a89a6c053e3be13fe62ed844f8b4cff6dfe834b
MAILBOX_ROOT="$(pwd -P)"
RESULT_61="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_61.txt"
RESULT_61_COMMIT=3d14c340e4b0bbdffabff0c98b18254203329d17
RESULT_61_COMMAND_COMMIT=0ef2f86a902fcc9a13192fd234e696e996b142fb
RESULT_61_SIZE=1588
RESULT_61_SHA=3df3bbdfdfc49beb220a618ee439525f5431250e15e5f3a62790a256c3957d2d
RESULT_62="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_62.txt"
RESULT_62_COMMIT=3ce9a6551d261a2b9036d0001dfa2e6471a75271
RESULT_62_COMMAND_COMMIT=5a2834fa9b5acf7417bb409be948f3c7f341695c
RESULT_62_COMMAND_SHA=0396a10f3f128de6bda31ad6bf594fe9441b044ab4819a3630017612b1bcf285
RESULT_62_SIZE=298
RESULT_62_SHA=2521c2e8b6c814dde2f64451435fd100951efb7fe3d0e191a34fd8b3acb8c4c4
JOB_NAME=tukf09-455-v2r5-map
JOB_ID_FILE="${ROOT}/status/allocation_probe_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/allocation_probe_submission.lock"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SEQUENCE 61 DEPLOYMENT EVIDENCE ==="
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"
[[ -f "${RESULT_61}" && ! -L "${RESULT_61}" ]] || fail "sequence 61 result missing or linked"
[[ "$(stat -c '%h' "${RESULT_61}")" -eq 1 ]] || fail "sequence 61 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_61}")" -eq "${RESULT_61_SIZE}" ]] || fail "sequence 61 result size changed"
[[ "$(sha256sum "${RESULT_61}" | awk '{print $1}')" = "${RESULT_61_SHA}" ]] || fail "sequence 61 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_61.txt)" = "${RESULT_61_COMMIT}" ]] || fail "sequence 61 result commit changed"
git merge-base --is-ancestor "${RESULT_61_COMMAND_COMMIT}" "${RESULT_61_COMMIT}" || fail "sequence 61 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_61_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${RESULT_61_COMMAND_COMMIT}" ]] || fail "sequence 61 command was not the last channel command before its result"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_61_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_61.txt" ]] || fail "sequence 61 result commit surface changed"

"${PYTHON}" -B - "${RESULT_61}" "${ROOT}" <<'PY'
import json
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
root = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=61"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert "TUKF09_455_A800_EXCLUSIVE_V2R5_DEPLOYMENT_COMPLETED_NO_JOB_SUBMITTED_FORMAL_EVALUATION_HOLD" in lines
records = [json.loads(line) for line in lines if line.startswith("{")]
assert records == [{
    "archive_sha256": "41b07596b8d2a092cdc5878787c10525e31a18e0d549f523dee1717b8c3d974c",
    "bundle_manifest_sha256": "f7c18d0a95849ee1d7d0a64c7a8724b6cf1fc0b84967503bd7ec1b484b239e76",
    "command_sha256": "21b1c0541fbfb5f5b26e3fc435256ec213772843fb19b258eda1df1527bab5ea",
    "deployment_mailbox_sequence": 61,
    "evaluation_array_reads": 0,
    "evaluation_metrics": 0,
    "evaluation_outputs": 0,
    "evaluation_predictions": 0,
    "formal_evaluation_authorized": False,
    "member_count": 2808,
    "neural_model_units": 0,
    "offline_runtime_input_file_count": 0,
    "outer_manifest_sha256": "918f7dedc6990da454ce308993918714c32512524699a00237c45afe2725391b",
    "preserved_failed_v2r4_job_id": 217409,
    "remote_root": root,
    "slurm_job_submitted": False,
    "source_capsule_data_identity_sha256": "dd238eebc1696f73f9eee7adf924913ff5a912c8f795f8998255e87408b760da",
    "source_capsule_post_publication_audit_mailbox_sequence": 47,
    "status": "A800_EXCLUSIVE_V2R5_RUNTIME_PORTABILITY_REPAIR_DEPLOYED_STRICT_BUNDLE_AND_SOURCE_CAPSULE_VERIFIED_FORMAL_EVALUATION_HOLD",
}]
PY

echo "=== FROZEN SEQUENCE 62 PRE-SUBMISSION FAILURE EVIDENCE ==="
[[ -f "${RESULT_62}" && ! -L "${RESULT_62}" ]] || fail "sequence 62 result missing or linked"
[[ "$(stat -c '%h' "${RESULT_62}")" -eq 1 ]] || fail "sequence 62 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_62}")" -eq "${RESULT_62_SIZE}" ]] || fail "sequence 62 result size changed"
[[ "$(sha256sum "${RESULT_62}" | awk '{print $1}')" = "${RESULT_62_SHA}" ]] || fail "sequence 62 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_62.txt)" = "${RESULT_62_COMMIT}" ]] || fail "sequence 62 result commit changed"
git merge-base --is-ancestor "${RESULT_62_COMMAND_COMMIT}" "${RESULT_62_COMMIT}" || fail "sequence 62 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_62_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${RESULT_62_COMMAND_COMMIT}" ]] || fail "sequence 62 command was not the last channel command before its result"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_62_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_62.txt" ]] || fail "sequence 62 result commit surface changed"
[[ "$(git show "${RESULT_62_COMMAND_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${RESULT_62_COMMAND_SHA}" ]] || fail "sequence 62 command hash changed"

"${PYTHON}" -B - "${RESULT_62}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
assert len(lines) == 9
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=62"
assert lines[1] == "### host=login4"
assert lines[2].startswith("### started=")
assert lines[3] == "### ---------- output ----------"
assert lines[4] == "=== FROZEN SEQUENCE 61 DEPLOYMENT EVIDENCE ==="
assert lines[5] == "FATAL: sequence 61 result parent changed"
assert lines[6] == "### ---------- end ----------"
assert lines[7] == "### exit_code=1"
assert lines[8].startswith("### finished=")
assert "Submitted batch job" not in "\n".join(lines)
assert "ALLOCATION_PROBE_JOB_ID=" not in "\n".join(lines)
PY

echo "=== IMMUTABLE DEPLOYMENT AND CONTRACT GATES ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing or linked: ${item}"
done
for item in "${PROBE_SCRIPT}" "${EXECUTION_CONFIG}" "${DEPLOYMENT_SUMMARY}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required file missing or linked: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required file hard-linked: ${item}"
done
[[ "$(sha256sum "${PROBE_SCRIPT}" | awk '{print $1}')" = "${PROBE_SCRIPT_SHA}" ]] || fail "allocation probe hash mismatch"
[[ "$(sha256sum "${EXECUTION_CONFIG}" | awk '{print $1}')" = "${EXECUTION_CONFIG_SHA}" ]] || fail "execution config hash mismatch"
[[ "$(stat -c '%s' "${DEPLOYMENT_SUMMARY}")" -eq "${DEPLOYMENT_SUMMARY_SIZE}" ]] || fail "deployment summary size mismatch"
[[ "$(sha256sum "${DEPLOYMENT_SUMMARY}" | awk '{print $1}')" = "${DEPLOYMENT_SUMMARY_SHA}" ]] || fail "deployment summary hash mismatch"

"${PYTHON}" -B - "${DEPLOYMENT_SUMMARY}" "${EXECUTION_CONFIG}" "${ROOT}" <<'PY'
import json
import os
from pathlib import Path
import sys

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
config = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
root = Path(sys.argv[3])
assert summary["status"] == "A800_EXCLUSIVE_V2R5_RUNTIME_PORTABILITY_REPAIR_DEPLOYED_STRICT_BUNDLE_AND_SOURCE_CAPSULE_VERIFIED_FORMAL_EVALUATION_HOLD"
assert summary["deployment_mailbox_sequence"] == 61
assert summary["slurm_job_submitted"] is False
assert summary["formal_evaluation_authorized"] is False
assert summary["neural_model_units"] == 0
for field in ("evaluation_array_reads", "evaluation_predictions", "evaluation_metrics", "evaluation_outputs"):
    assert type(summary[field]) is int and summary[field] == 0
assert config["schema_version"] == "tukf09_455_basin_hpc_execution_a800_exclusive_v2r5"
assert config["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert config["technical_retry"]["revision"] == "v2r5"
assert config["technical_retry"]["failed_training_job_id"] == 217409
assert config["technical_retry"]["retry_failed_v2r4_root_allowed"] is False
assert config["technical_retry"]["scientific_contract_changed"] is False
assert config["technical_retry"]["formal_evaluation_authorized"] is False
assert config["execution_route"]["formal_evaluation_access"] is False
assert config["execution_route"]["neural_model_parallelism"] == 1
assert config["scientific_identity"]["ordered_basin_count"] == 455
assert config["scientific_identity"]["excluded_basins"] == ["08202700"]
assert config["expected_completion"]["neural_model_units"] == 9
for field in ("evaluation_array_reads", "evaluation_predictions", "evaluation_metrics", "evaluation_outputs"):
    assert type(config["expected_completion"][field]) is int
    assert config["expected_completion"][field] == 0
for relative in (
    "offline_inputs_v2r5",
    "runtime_v2r5",
    "status/PREPARATION_FAILED.json",
    "status/allocation_probe.json",
    "status/allocation_probe_job_id.txt",
    "status/allocation_probe_submission.lock",
    "status/initial_bundle_verification.json",
    "status/staged_training_sources.json",
    "status/preparation_probe.json",
    "status/hpc_technical_admission.json",
    "status/preparation.lock",
    "status/preparation_job_id.txt",
    "status/training_submission.lock",
    "status/training_job_id.txt",
):
    assert not os.path.lexists(root / relative), relative
results = root / "bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
for name in ("selection", "evaluation", "independent", "formal_evaluation", "formal_evaluation_independent"):
    assert not os.path.lexists(results / name), name
PY

shopt -s nullglob
runtime_pending=("${ROOT}"/runtime_v2r5.pending.*)
shopt -u nullglob
[[ "${#runtime_pending[@]}" -eq 0 ]] || fail "private-runtime pending path already exists"
if compgen -G "${ROOT}/logs/allocation-probe-*.out" >/dev/null || compgen -G "${ROOT}/logs/allocation-probe-*.err" >/dev/null; then
  fail "allocation-probe logs already exist"
fi

echo "=== SAME-NAME JOB GATE ==="
set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot inspect current jobs: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name allocation probe already exists: ${same_name}"

echo "=== EXCLUSIVE ALLOCATION SUBMISSION LOCK ==="
mkdir "${SUBMISSION_LOCK}" || fail "cannot acquire allocation submission lock"
[[ -d "${SUBMISSION_LOCK}" && ! -L "${SUBMISSION_LOCK}" ]] || fail "allocation submission lock linked or irregular"
[[ ! -e "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "allocation job id record already exists"
set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot recheck jobs after lock acquisition: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name allocation probe appeared after lock acquisition: ${same_name}"

echo "=== EXACTLY ONE PACKAGE ALLOCATION PROBE SUBMISSION ==="
set +e
submit_output=$(sbatch "${PROBE_SCRIPT}" 2>&1)
submit_rc=$?
set -e
printf '%s\n' "${submit_output}"
job_ids=$(printf '%s\n' "${submit_output}" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
job_id_count=$(printf '%s\n' "${job_ids}" | awk 'NF{count++} END{print count+0}')
[[ "${submit_rc}" -eq 0 && "${job_id_count}" -eq 1 ]] || fail "allocation submission not proven exactly once"
job_id=$(printf '%s\n' "${job_ids}" | awk 'NF{print; exit}')
[[ "${job_id}" =~ ^[0-9]+$ ]] || fail "invalid allocation-probe job id"

"${PYTHON}" -B - "${JOB_ID_FILE}" "${job_id}" <<'PY'
import os
from pathlib import Path
import stat
import sys

path = Path(sys.argv[1])
content = (sys.argv[2] + "\n").encode("ascii")
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
try:
    remaining = memoryview(content)
    while remaining:
        written = os.write(fd, remaining)
        assert written > 0
        remaining = remaining[written:]
    os.fsync(fd)
finally:
    os.close(fd)
info = os.lstat(path)
assert stat.S_ISREG(info.st_mode) and info.st_nlink == 1
assert path.read_bytes() == content
directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(directory_fd)
finally:
    os.close(directory_fd)
PY
chmod 0444 "${JOB_ID_FILE}"

echo "=== IMMEDIATE STATE ==="
echo "ALLOCATION_PROBE_JOB_ID=${job_id}"
squeue -j "${job_id}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true
echo "TUKF09_455_A800_EXCLUSIVE_V2R5_ALLOCATION_PROBE_SUBMITTED_ONCE_FORMAL_EVALUATION_HOLD"
