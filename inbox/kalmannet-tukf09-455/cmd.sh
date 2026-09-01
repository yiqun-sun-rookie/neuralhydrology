#!/bin/bash
# Submit exactly one package-native v2r4 allocation probe. This command does
# not acquire or install a runtime, stage data, train a model, or run formal
# evaluation.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r4_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
PROBE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/allocation_probe.slurm"
PROBE_SCRIPT_SHA=9c6f3992205793070ebbefd0ee2362ceca8fe6c7669b71dc32547fc2e9881dab
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r4.json"
EXECUTION_CONFIG_SHA=54bb8226621c440983d1a8f4d1291b9980488296bc9658085abef47efe56b3f6
DEPLOYMENT_SUMMARY="${ROOT}/status/deployment_summary.json"
DEPLOYMENT_SUMMARY_SIZE=1109
DEPLOYMENT_SUMMARY_SHA=14df1ee8339b15caad43298f396c2f26c174f71718d08681f1cd21de0b8ca794
MAILBOX_ROOT="$(pwd -P)"
RESULT_48="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_48.txt"
RESULT_48_COMMIT=86b5593feb4fe824a46c62c6dc98b3733fef22b9
RESULT_48_PARENT=1381e6a0969ba87a90fbeb0e5d44669f3856f437
RESULT_48_SIZE=1350
RESULT_48_SHA=5e9376bf0e2b95a94198dd2ece22d42487b67e0674506a28f63333939bd5cb03
JOB_NAME=tukf09-455-v2r4-map
JOB_ID_FILE="${ROOT}/status/allocation_probe_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/allocation_probe_submission.lock"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== SEQUENCE 48 DEPLOYMENT EVIDENCE ==="
[[ -f "${RESULT_48}" && ! -L "${RESULT_48}" ]] || fail "sequence 48 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_48}")" -eq 1 ]] || fail "sequence 48 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_48}")" -eq "${RESULT_48_SIZE}" ]] || fail "sequence 48 result size changed"
[[ "$(sha256sum "${RESULT_48}" | awk '{print $1}')" = "${RESULT_48_SHA}" ]] || fail "sequence 48 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_48.txt)" = "${RESULT_48_COMMIT}" ]] || fail "sequence 48 result commit changed"
[[ "$(git rev-parse "${RESULT_48_COMMIT}^")" = "${RESULT_48_PARENT}" ]] || fail "sequence 48 result parent changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_48_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_48.txt" ]] || fail "sequence 48 result commit surface changed"
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"

"${PYTHON}" -B - "${RESULT_48}" "${ROOT}" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
root = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=48"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert "TUKF09_455_A800_EXCLUSIVE_V2R4_DEPLOYMENT_COMPLETED_NO_JOB_SUBMITTED" in lines
records = [json.loads(line) for line in lines if line.startswith("{")]
assert len(records) == 1
record = records[0]
expected = {
    "archive_sha256": "0f6b3087a976831cb87fc95b3f449318e72f1b198c7c4c13eed04808d43bda7b",
    "bundle_manifest_sha256": "97eccb8c689e1c1b22577ba8823a8fb0802a14f10db213f861c5b9e3b504bdc1",
    "command_sha256": "9a00f000d675740be6be866065b28452107edca2acd558a2806614c496e4e460",
    "deployment_mailbox_sequence": 48,
    "evaluation_array_reads": 0,
    "evaluation_metrics": 0,
    "evaluation_outputs": 0,
    "evaluation_predictions": 0,
    "formal_evaluation_authorized": False,
    "member_count": 2808,
    "neural_model_units": 0,
    "offline_runtime_input_file_count": 0,
    "outer_manifest_sha256": "0db32e49a6f803f375ad9497e1ab4b694a91a4a858074452a79a401a5521ce84",
    "remote_root": root,
    "slurm_job_submitted": False,
    "source_capsule_data_identity_sha256": "dd238eebc1696f73f9eee7adf924913ff5a912c8f795f8998255e87408b760da",
    "source_capsule_post_publication_audit_mailbox_sequence": 47,
    "status": "A800_EXCLUSIVE_V2R4_DEPLOYED_STRICT_BUNDLE_AND_SOURCE_CAPSULE_VERIFIED_FORMAL_EVALUATION_HOLD",
}
assert record == expected
for field in (
    "evaluation_array_reads",
    "evaluation_predictions",
    "evaluation_metrics",
    "evaluation_outputs",
):
    assert type(record[field]) is int and record[field] == 0
assert record["slurm_job_submitted"] is False
PY

echo "=== IMMUTABLE DEPLOYMENT AND CONTRACT GATES ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
for item in "${PROBE_SCRIPT}" "${EXECUTION_CONFIG}" "${DEPLOYMENT_SUMMARY}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required deployed file missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required deployed file hard-link count changed: ${item}"
done
[[ "$(sha256sum "${PROBE_SCRIPT}" | awk '{print $1}')" = "${PROBE_SCRIPT_SHA}" ]] || fail "package allocation probe hash mismatch"
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
root_arg = sys.argv[3]
root = Path(root_arg)
assert summary == {
    "archive_sha256": "0f6b3087a976831cb87fc95b3f449318e72f1b198c7c4c13eed04808d43bda7b",
    "bundle_manifest_sha256": "97eccb8c689e1c1b22577ba8823a8fb0802a14f10db213f861c5b9e3b504bdc1",
    "command_sha256": "9a00f000d675740be6be866065b28452107edca2acd558a2806614c496e4e460",
    "deployment_mailbox_sequence": 48,
    "evaluation_array_reads": 0,
    "evaluation_metrics": 0,
    "evaluation_outputs": 0,
    "evaluation_predictions": 0,
    "formal_evaluation_authorized": False,
    "member_count": 2808,
    "neural_model_units": 0,
    "offline_runtime_input_file_count": 0,
    "outer_manifest_sha256": "0db32e49a6f803f375ad9497e1ab4b694a91a4a858074452a79a401a5521ce84",
    "remote_root": root_arg,
    "slurm_job_submitted": False,
    "source_capsule_data_identity_sha256": "dd238eebc1696f73f9eee7adf924913ff5a912c8f795f8998255e87408b760da",
    "source_capsule_post_publication_audit_mailbox_sequence": 47,
    "status": "A800_EXCLUSIVE_V2R4_DEPLOYED_STRICT_BUNDLE_AND_SOURCE_CAPSULE_VERIFIED_FORMAL_EVALUATION_HOLD",
}
for field in (
    "evaluation_array_reads",
    "evaluation_predictions",
    "evaluation_metrics",
    "evaluation_outputs",
):
    assert type(summary[field]) is int and summary[field] == 0
assert config["schema_version"] == "tukf09_455_basin_hpc_execution_a800_exclusive_v2r4"
assert config["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert config["status"] == "HPC_TECHNICAL_EXECUTION_FROZEN_FORMAL_EVALUATION_HOLD"
assert config["technical_retry"]["revision"] == "v2r4"
assert config["technical_retry"]["scientific_contract_changed"] is False
assert config["technical_retry"]["formal_evaluation_authorized"] is False
assert config["training_source_capsule"]["data_file_count"] == 911
assert config["training_source_capsule"]["data_identity_sha256"] == "dd238eebc1696f73f9eee7adf924913ff5a912c8f795f8998255e87408b760da"
assert config["training_source_capsule"]["post_publication_audit_mailbox_sequence"] == 47
for field in (
    "formal_evaluation_array_reads",
    "formal_evaluation_predictions",
    "formal_evaluation_metrics",
    "formal_evaluation_outputs",
):
    assert type(config["training_source_capsule"][field]) is int
    assert config["training_source_capsule"][field] == 0
assert config["execution_route"]["formal_evaluation_access"] is False
assert config["execution_route"]["neural_model_parallelism"] == 1
assert config["scientific_identity"]["ordered_basin_count"] == 455
assert config["scientific_identity"]["excluded_basins"] == ["08202700"]
assert config["slurm"]["exclusive_node"] is True
assert config["slurm"]["gpus"] == 1
assert config["expected_completion"]["neural_model_units"] == 9
for field in (
    "evaluation_array_reads",
    "evaluation_predictions",
    "evaluation_metrics",
    "evaluation_outputs",
):
    assert type(config["expected_completion"][field]) is int
    assert config["expected_completion"][field] == 0
assert "read_formal_evaluation_arrays" in config["forbidden_actions"]
assert "run_formal_evaluation" in config["forbidden_actions"]
for relative in (
    "offline_inputs_v2r4",
    "runtime_v2r4",
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
    assert not os.path.lexists(root / relative), f"pre-allocation output already exists: {relative}"
results = root / "bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
for name in (
    "selection",
    "evaluation",
    "independent",
    "formal_evaluation",
    "formal_evaluation_independent",
):
    assert not os.path.lexists(results / name), f"forbidden evaluation output exists: {name}"
PY

shopt -s nullglob
runtime_pending=("${ROOT}"/runtime_v2r4.pending.*)
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
same_name=$(printf '%s
' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name allocation probe already exists: ${same_name}"

echo "=== EXCLUSIVE ALLOCATION SUBMISSION LOCK ==="
mkdir "${SUBMISSION_LOCK}" || fail "cannot acquire the allocation submission lock"
[[ -d "${SUBMISSION_LOCK}" && ! -L "${SUBMISSION_LOCK}" ]] || fail "allocation submission lock is linked or irregular"
[[ ! -e "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "allocation job id record appeared after lock acquisition"
set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot recheck jobs after lock acquisition: ${squeue_output}"
same_name=$(printf '%s
' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name allocation probe appeared after lock acquisition: ${same_name}"

echo "=== EXACTLY ONE PACKAGE ALLOCATION PROBE SUBMISSION ==="
set +e
submit_output=$(sbatch "${PROBE_SCRIPT}" 2>&1)
submit_rc=$?
set -e
printf '%s
' "${submit_output}"
job_ids=$(printf '%s
' "${submit_output}" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
job_id_count=$(printf '%s
' "${job_ids}" | awk 'NF{count++} END{print count+0}')
[[ "${submit_rc}" -eq 0 && "${job_id_count}" -eq 1 ]] || fail "allocation submission not proven exactly once (wrapper_rc=${submit_rc}, parsed_count=${job_id_count})"
job_id=$(printf '%s
' "${job_ids}" | awk 'NF{print; exit}')
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
sync -f "${JOB_ID_FILE}"

echo "=== IMMEDIATE STATE ==="
echo "ALLOCATION_PROBE_JOB_ID=${job_id}"
squeue -j "${job_id}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true
echo "TUKF09_455_A800_EXCLUSIVE_V2R4_ALLOCATION_PROBE_SUBMITTED_ONCE"
