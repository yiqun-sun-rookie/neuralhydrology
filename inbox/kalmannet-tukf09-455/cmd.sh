#!/bin/bash
# Freeze the passed v2r5 technical admission, reverify every training gate, and
# submit exactly one exclusive A800 neural-training job. Formal evaluation stays closed.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
RUNTIME_ROOT="${ROOT}/runtime_v2r5"
PRIVATE_MANIFEST="${RUNTIME_ROOT}/evidence/private_runtime_manifest.json"
OFFLINE_INPUT_MANIFEST="${ROOT}/offline_inputs_v2r5/manifest.json"
STAGED_MANIFEST="${ROOT}/status/staged_training_sources.json"
PREPARATION_PROBE="${ROOT}/status/preparation_probe.json"
INITIAL_BUNDLE="${ROOT}/status/initial_bundle_verification.json"
FILTER_SEAL="${RESULTS_ROOT}/control/filter_rebinding/independent/manifest.final.sha256.json"
ADMISSION="${ROOT}/status/hpc_technical_admission.json"
BUNDLE_MANIFEST="${ROOT}/bundle/bundle_manifest.json"
BUILDER="${PROJECT_ROOT}/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r5.py"
TRAINING_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/submit_training_gpu.slurm"
STAGE_TOOL="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/stage_and_train.py"
VERIFIER="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/verify_result.py"
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r5.json"

PREPARATION_JOB_ID=217817
PREPARATION_JOB_NAME=tukf09-455-v2r5-prepare
PREPARATION_JOB_ID_FILE="${ROOT}/status/preparation_job_id.txt"
PREPARATION_SUBMISSION_LOCK="${ROOT}/status/preparation_submission.lock"
TRAINING_JOB_NAME=tukf09-455-v2r5-neural
TRAINING_JOB_ID_FILE="${ROOT}/status/training_job_id.txt"
TRAINING_SUBMISSION_LOCK="${ROOT}/status/training_submission.lock"

ADMISSION_SHA=12ee428324ce43c7fbbff59115022e1005a05fff800fd3203c2203cb8428514e
ADMISSION_IDENTITY_SHA=948a161ea7bcf78febc05374724cd20563fdebf89178f21cf676d38a9806158a
BUILDER_SHA=294b43a0292a1cad655f207028fdeeb32e434aa221174b90e35843b5f2e90bc6
TRAINING_SCRIPT_SHA=d679c606425761e64f53e5d1489354afcaef67e4f8b29ddccbdce012a26999b9
STAGE_TOOL_SHA=b3ba14eae1a32280d94530c316cea4bc8449a9d5bce41f8ca31cec931888bc81
VERIFIER_SHA=43a54205d220cec2d43ba0c3b862be1e9d0328b60d993e72a0e75d34526520ba
EXECUTION_CONFIG_SHA=5c1cdc50d28fde46b92947a1fa0fb628a177f7ad573fcea4f943d55934a04bc7
BUNDLE_MANIFEST_SHA=f7c18d0a95849ee1d7d0a64c7a8724b6cf1fc0b84967503bd7ec1b484b239e76
PRIVATE_MANIFEST_SHA=4207579e6a7af408da933ff1075d537186878cbbcb4b0f17e8778b6a47a98aee
OFFLINE_INPUT_MANIFEST_SHA=2507f0ea14c4880c4aad9a3ccd5a2e6e1c5e5be1ee18bd0093c52d5db85acf82
PREPARATION_PROBE_SHA=59007f5d207f6dd5d9a1225f11d817fd3aabf04ff1690511705fe4546c4222fe
STAGED_MANIFEST_SHA=fecab69d1ce6fa0b23c2f5b22203a31d87b1c53264fe41a2092c8a2f87e5c0b9
INITIAL_BUNDLE_SHA=8bd135e5b5b0cc61fe328aaba1afe3521f3293e629697d32a1c2234794d4f27f
FILTER_SEAL_SHA=7ecfa4d5a61f37a2fc40e75b9e1bbec4be6c39ba7b0b87ec8705bcca277faaa0

MAILBOX_ROOT="$(pwd -P)"
RESULT_69="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_69.txt"
RESULT_69_COMMIT=14c347ccdbc7523ddc4105bf281af6793e98cc06
RESULT_69_COMMAND_COMMIT=19b26880e6d100aabeb33419ae05b6c2bae8bd9e
RESULT_69_COMMAND_SHA=b31a56ba57bb56bf7354ec9b23cc0ba667e14c913223ab5d4849baa8553a53cc
RESULT_69_SIZE=8955
RESULT_69_SHA=a37a1ee1bdcefb3e5d40fcbdaf6161836f1dbb5e8863f4e95659141f00c0adc6

PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${PROJECT_ROOT}"

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SEQUENCE 69 TECHNICAL ADMISSION EVIDENCE ==="
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"
[[ -f "${RESULT_69}" && ! -L "${RESULT_69}" ]] || fail "sequence 69 result missing or linked"
[[ "$(stat -c '%h' "${RESULT_69}")" -eq 1 ]] || fail "sequence 69 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_69}")" -eq "${RESULT_69_SIZE}" ]] || fail "sequence 69 result size changed"
[[ "$(sha256sum "${RESULT_69}" | awk '{print $1}')" = "${RESULT_69_SHA}" ]] || fail "sequence 69 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_69.txt)" = "${RESULT_69_COMMIT}" ]] || fail "sequence 69 result commit changed"
git merge-base --is-ancestor "${RESULT_69_COMMAND_COMMIT}" "${RESULT_69_COMMIT}" || fail "sequence 69 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_69_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${RESULT_69_COMMAND_COMMIT}" ]] || fail "sequence 69 command was not the last channel command before its result"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_69_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_69.txt" ]] || fail "sequence 69 result commit surface changed"
[[ "$(git show "${RESULT_69_COMMAND_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${RESULT_69_COMMAND_SHA}" ]] || fail "sequence 69 command hash changed"

"${PYTHON}" -B - "${RESULT_69}" <<'PY'
from pathlib import Path
import json
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=69"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert "ADMISSION_SIZE=5203" in lines
assert "ADMISSION_SHA256=12ee428324ce43c7fbbff59115022e1005a05fff800fd3203c2203cb8428514e" in lines
assert "TUKF09_455_A800_EXCLUSIVE_V2R5_TECHNICAL_ADMISSION_CREATED_AND_VERIFIED_TRAINING_NOT_SUBMITTED_FORMAL_EVALUATION_HOLD" in lines
summary = next(json.loads(line) for line in lines if line.startswith('{"admission_identity_sha256"'))
assert summary == {
    "admission_identity_sha256": "948a161ea7bcf78febc05374724cd20563fdebf89178f21cf676d38a9806158a",
    "admission_sha256": "12ee428324ce43c7fbbff59115022e1005a05fff800fd3203c2203cb8428514e",
    "evaluation_array_reads": 0,
    "evaluation_metrics": 0,
    "evaluation_outputs": 0,
    "evaluation_predictions": 0,
    "formal_evaluation_authorized": False,
    "neural_model_unit_count": 9,
    "ordered_basin_count": 455,
    "status": "HPC_A800_EXCLUSIVE_V2R5_TECHNICAL_EXECUTION_ADMITTED_FORMAL_EVALUATION_HOLD",
}
assert not any(line.startswith("FATAL:") for line in lines)
PY

echo "=== PREPARATION JOB REMAINS COMPLETED ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status" "${RUNTIME_ROOT}" "${PREPARATION_SUBMISSION_LOCK}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing or linked: ${item}"
done
[[ -f "${PREPARATION_JOB_ID_FILE}" && ! -L "${PREPARATION_JOB_ID_FILE}" ]] || fail "preparation job id record missing or linked"
[[ "$(tr -d '\r\n' < "${PREPARATION_JOB_ID_FILE}")" = "${PREPARATION_JOB_ID}" ]] || fail "preparation job id record mismatch"
sacct_output=$(sacct -j "${PREPARATION_JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,NodeList,Elapsed,Start,End 2>&1) || fail "sacct failed: ${sacct_output}"
printf '%s\n' "${sacct_output}"
job_row=$(printf '%s\n' "${sacct_output}" | awk -F'|' -v id="${PREPARATION_JOB_ID}" '$1==id {print; found=1} END {exit(found ? 0 : 1)}') || fail "exact preparation job row missing"
[[ "$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $2}')" = "${PREPARATION_JOB_NAME}" ]] || fail "preparation job name mismatch"
[[ "$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $3}')" = "hgpu8" ]] || fail "preparation partition mismatch"
[[ "$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $4}')" = "COMPLETED" ]] || fail "preparation job is not completed"
[[ "$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $5}')" = "0:0" ]] || fail "preparation job exit code changed"

echo "=== FROZEN TRAINING SUBMISSION GATES ==="
for item in \
  "${BUILDER}" \
  "${TRAINING_SCRIPT}" \
  "${STAGE_TOOL}" \
  "${VERIFIER}" \
  "${EXECUTION_CONFIG}" \
  "${BUNDLE_MANIFEST}" \
  "${ADMISSION}" \
  "${PRIVATE_MANIFEST}" \
  "${OFFLINE_INPUT_MANIFEST}" \
  "${PREPARATION_PROBE}" \
  "${STAGED_MANIFEST}" \
  "${INITIAL_BUNDLE}" \
  "${FILTER_SEAL}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required training evidence missing or linked: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required training evidence hard-link count changed: ${item}"
done
[[ "$(sha256sum "${BUILDER}" | awk '{print $1}')" = "${BUILDER_SHA}" ]] || fail "strict bundle verifier hash changed"
[[ "$(sha256sum "${TRAINING_SCRIPT}" | awk '{print $1}')" = "${TRAINING_SCRIPT_SHA}" ]] || fail "training Slurm wrapper hash changed"
[[ "$(sha256sum "${STAGE_TOOL}" | awk '{print $1}')" = "${STAGE_TOOL_SHA}" ]] || fail "training controller hash changed"
[[ "$(sha256sum "${VERIFIER}" | awk '{print $1}')" = "${VERIFIER_SHA}" ]] || fail "training result verifier hash changed"
[[ "$(sha256sum "${EXECUTION_CONFIG}" | awk '{print $1}')" = "${EXECUTION_CONFIG_SHA}" ]] || fail "HPC execution config hash changed"
[[ "$(sha256sum "${BUNDLE_MANIFEST}" | awk '{print $1}')" = "${BUNDLE_MANIFEST_SHA}" ]] || fail "bundle manifest hash changed"
[[ "$(sha256sum "${ADMISSION}" | awk '{print $1}')" = "${ADMISSION_SHA}" ]] || fail "technical admission hash changed"
[[ "$(sha256sum "${PRIVATE_MANIFEST}" | awk '{print $1}')" = "${PRIVATE_MANIFEST_SHA}" ]] || fail "private runtime manifest hash changed"
[[ "$(sha256sum "${OFFLINE_INPUT_MANIFEST}" | awk '{print $1}')" = "${OFFLINE_INPUT_MANIFEST_SHA}" ]] || fail "offline input manifest hash changed"
[[ "$(sha256sum "${PREPARATION_PROBE}" | awk '{print $1}')" = "${PREPARATION_PROBE_SHA}" ]] || fail "preparation probe hash changed"
[[ "$(sha256sum "${STAGED_MANIFEST}" | awk '{print $1}')" = "${STAGED_MANIFEST_SHA}" ]] || fail "staged source manifest hash changed"
[[ "$(sha256sum "${INITIAL_BUNDLE}" | awk '{print $1}')" = "${INITIAL_BUNDLE_SHA}" ]] || fail "initial bundle verification hash changed"
[[ "$(sha256sum "${FILTER_SEAL}" | awk '{print $1}')" = "${FILTER_SEAL_SHA}" ]] || fail "remote filter seal hash changed"

echo "=== REPAIRED RUNTIME BUNDLE VERIFICATION ==="
"${PYTHON}" -B "${BUILDER}" --verify-runtime "${ROOT}/bundle"

echo "=== INDEPENDENT TECHNICAL ADMISSION REVERIFICATION ==="
"${PYTHON}" -B - "${PROJECT_ROOT}" "${ADMISSION}" "${PRIVATE_MANIFEST}" "${PREPARATION_PROBE}" "${STAGED_MANIFEST}" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

project = Path(sys.argv[1])
admission_path = Path(sys.argv[2])
private_path = Path(sys.argv[3])
probe_path = Path(sys.argv[4])
staged_path = Path(sys.argv[5])
stage_path = project / "hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/stage_and_train.py"
spec = importlib.util.spec_from_file_location("tukf09_stage_v2r5_presubmit_audit", stage_path)
assert spec is not None and spec.loader is not None
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)
config_path = project / "configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r5.json"
config = stage.load_execution_config(config_path)
admission = stage.read_json(admission_path, root=Path(config["remote_layout"]["remote_root"]), canonical=True)
stage._verify_payload_identity(admission, label="HPC technical admission")
stage.require_zero_evaluation(admission, label="HPC technical admission")
verified = stage.verify_hpc_technical_admission(
    project_root=project,
    admission_path=admission_path,
    private_manifest=private_path,
    probe_path=probe_path,
    staged_manifest=staged_path,
    current_runtime=admission["admitted_runtime"],
    config_path=config_path,
)
assert admission["status"] == "HPC_A800_EXCLUSIVE_V2R5_TECHNICAL_EXECUTION_ADMITTED_FORMAL_EVALUATION_HOLD"
assert admission["identity_sha256"] == "948a161ea7bcf78febc05374724cd20563fdebf89178f21cf676d38a9806158a"
assert stage.sha256_file(admission_path) == "12ee428324ce43c7fbbff59115022e1005a05fff800fd3203c2203cb8428514e"
assert admission["local_filter_installation_final_sha256"] == "b378ffbfde4d24ded8fbb42fdf10fef59eb04100c93879a41b4d538ae36f6ba0"
assert admission["remote_filter_installation_final_sha256"] == "7ecfa4d5a61f37a2fc40e75b9e1bbec4be6c39ba7b0b87ec8705bcca277faaa0"
assert admission["ordered_basin_count"] == 455
assert admission["neural_model_order"] == [f"lead_{lead}_seed_{seed}" for lead in (1, 2, 3) for seed in (0, 1, 2)]
assert admission["neural_model_parallelism"] == 1
assert admission["exclusive_node_required"] is True
assert admission["exclusive_node_runtime_evidence_passed"] is True
assert admission["formal_evaluation_authorized"] is False
assert admission["admitted_runtime"]["slurm_job_id"] == "217817"
assert verified["identity_sha256"] == admission["identity_sha256"]
assert config["scientific_identity"]["formal_training_execution"]["sha256"] == "0daf464f6bb1cfc11f04806b7caf5195ea42c3aef8187d8248474993ca108319"
print(json.dumps({
    "admission_identity_sha256": admission["identity_sha256"],
    "admission_sha256": stage.sha256_file(admission_path),
    "formal_evaluation_authorized": admission["formal_evaluation_authorized"],
    "neural_model_parallelism": admission["neural_model_parallelism"],
    "neural_model_unit_count": len(admission["neural_model_order"]),
    "ordered_basin_count": admission["ordered_basin_count"],
    "status": admission["status"],
}, sort_keys=True))
PY

echo "=== FORMAL EVALUATION AND PRISTINE TRAINING HOLD ==="
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists before training: ${name}"
done
[[ ! -e "${RESULTS_ROOT}/neural" && ! -L "${RESULTS_ROOT}/neural" ]] || fail "neural training output already exists"
[[ ! -e "${TRAINING_SUBMISSION_LOCK}" && ! -L "${TRAINING_SUBMISSION_LOCK}" ]] || fail "training submission lock already exists"
[[ ! -e "${TRAINING_JOB_ID_FILE}" && ! -L "${TRAINING_JOB_ID_FILE}" ]] || fail "training job id record already exists"
if compgen -G "${ROOT}/logs/training-*.out" >/dev/null || compgen -G "${ROOT}/logs/training-*.err" >/dev/null; then
  fail "training logs already exist"
fi
if compgen -G "${ROOT}/status/training_verification*.json" >/dev/null; then
  fail "training verification already exists"
fi

echo "=== SAME-NAME TRAINING JOB GATE ==="
set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot inspect current jobs: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${TRAINING_JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name training job already exists: ${same_name}"

echo "=== EXCLUSIVE TRAINING SUBMISSION LOCK ==="
mkdir "${TRAINING_SUBMISSION_LOCK}" || fail "cannot acquire training submission lock"
[[ -d "${TRAINING_SUBMISSION_LOCK}" && ! -L "${TRAINING_SUBMISSION_LOCK}" ]] || fail "training submission lock is linked or irregular"
[[ ! -e "${TRAINING_JOB_ID_FILE}" && ! -L "${TRAINING_JOB_ID_FILE}" ]] || fail "training job id record appeared after lock acquisition"
set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot recheck jobs after lock acquisition: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${TRAINING_JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name training job appeared after lock acquisition: ${same_name}"

echo "=== EXACTLY ONE NEURAL TRAINING SUBMISSION ==="
set +e
submit_output=$(sbatch "${TRAINING_SCRIPT}" 2>&1)
submit_rc=$?
set -e
printf '%s\n' "${submit_output}"
job_ids=$(printf '%s\n' "${submit_output}" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
job_id_count=$(printf '%s\n' "${job_ids}" | awk 'NF{count++} END{print count+0}')
[[ "${submit_rc}" -eq 0 && "${job_id_count}" -eq 1 ]] || fail "training submission not proven exactly once (sbatch_rc=${submit_rc}, parsed_count=${job_id_count})"
training_job_id=$(printf '%s\n' "${job_ids}" | awk 'NF{print; exit}')
[[ "${training_job_id}" =~ ^[0-9]+$ ]] || fail "invalid training job id"

"${PYTHON}" -B - "${TRAINING_JOB_ID_FILE}" "${training_job_id}" <<'PY'
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
chmod 0444 "${TRAINING_JOB_ID_FILE}"

echo "=== IMMEDIATE TRAINING STATE ==="
echo "TRAINING_JOB_ID=${training_job_id}"
squeue -j "${training_job_id}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output appeared after training submission: ${name}"
done
echo "TUKF09_455_A800_EXCLUSIVE_V2R5_NEURAL_TRAINING_SUBMITTED_ONCE_FORMAL_EVALUATION_HOLD"
