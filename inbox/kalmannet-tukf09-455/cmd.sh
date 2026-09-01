#!/bin/bash
# Read-only state and, if terminal, strict evidence audit for the one v2r4
# preparation job. This command submits, cancels, or mutates nothing.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r4_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
STAGED_ROOT="${PROJECT_ROOT}/G:/github/pycharm/projects/neuralhydrology/data/camels_us"
RUNTIME_ROOT="${ROOT}/runtime_v2r4"
PRIVATE_MANIFEST="${RUNTIME_ROOT}/evidence/private_runtime_manifest.json"
INITIAL_BUNDLE="${ROOT}/status/initial_bundle_verification.json"
STAGED_MANIFEST="${ROOT}/status/staged_training_sources.json"
PREPARATION_PROBE="${ROOT}/status/preparation_probe.json"
PREPARATION_FAILED="${ROOT}/status/PREPARATION_FAILED.json"
FILTER_SEAL="${RESULTS_ROOT}/control/filter_rebinding/independent/manifest.final.sha256.json"
JOB_ID=217228
JOB_NAME=tukf09-455-v2r4-prepare
JOB_ID_FILE="${ROOT}/status/preparation_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/preparation_submission.lock"
STDOUT="${ROOT}/logs/prepare-${JOB_ID}.out"
STDERR="${ROOT}/logs/prepare-${JOB_ID}.err"
MAILBOX_ROOT="$(pwd -P)"
RESULT_52="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_52.txt"
RESULT_52_COMMIT=605a694a19d219a0deee03a5172de37a2d843407
RESULT_52_SIZE=890
RESULT_52_SHA=494c96538fd8cd60e1cbfb17775cfa77b3eb20844c55fbbb9f4713370ad1f5b5
SUBMISSION_COMMIT=8fa2fad8bf45052b5ffd151f9a303a6bb8e09d1f
SUBMISSION_COMMAND_SHA=b49982edfb884865462dffffa0dd44a2f4f0a06b867b9fdbecc73aacd75d915c
RESULT_53="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_53.txt"
RESULT_53_COMMIT=34609eb1546351904c042fb26e23ee28cac288dc
RESULT_53_SIZE=1109
RESULT_53_SHA=4fe2bf937e4a6e9065b404b8a2eff72ed7131be08ba40bc321ca2a22c2a2f24b
INSPECTION_53_COMMIT=2d0785fa89afb0bea55336273a7b7d0aa5265e28
INSPECTION_53_COMMAND_SHA=b6060fa1fb119101f13dca945c13159da7aba710741fce728ff4df870de76cf4
RESULT_54="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_54.txt"
RESULT_54_COMMIT=42067c4618f342c4240af5cbd2d33413cf647a01
RESULT_54_SIZE=1144
RESULT_54_SHA=80639f0725fe8111639b3988c855bd019249acb9b20d1df6dea117b34ea9942c
INSPECTION_54_COMMIT=ebb56d54ffd11f8ec0c6a90a8c16ce6793198e21
INSPECTION_54_COMMAND_SHA=d387b558c3ae1e705223d92cf3b704454cb521d535c0fe0ac4df612cac493fcb
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
export PYTHONNOUSERSITE=1
export PYTHONDWRITEBYTECODE=1
export PYTHONPATH="${PROJECT_ROOT}"

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SEQUENCE 52 SUBMISSION EVIDENCE ==="
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"
[[ -f "${RESULT_52}" && ! -L "${RESULT_52}" ]] || fail "sequence 52 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_52}")" -eq 1 ]] || fail "sequence 52 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_52}")" -eq "${RESULT_52_SIZE}" ]] || fail "sequence 52 result size changed"
[[ "$(sha256sum "${RESULT_52}" | awk '{print $1}')" = "${RESULT_52_SHA}" ]] || fail "sequence 52 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_52.txt)" = "${RESULT_52_COMMIT}" ]] || fail "sequence 52 result commit changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_52_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_52.txt" ]] || fail "sequence 52 result commit surface changed"
git merge-base --is-ancestor "${SUBMISSION_COMMIT}" "${RESULT_52_COMMIT}" || fail "sequence 52 submission is not an ancestor of its result"
[[ "$(git show "${SUBMISSION_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${SUBMISSION_COMMAND_SHA}" ]] || fail "sequence 52 submission command hash changed"

"${PYTHON}" -B - "${RESULT_52}" "${JOB_ID}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=52"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert lines.count(f"Submitted batch job {job_id}") == 1
assert f"PREPARATION_JOB_ID={job_id}" in lines
assert "TUKF09_455_A800_EXCLUSIVE_V2R4_OFFLINE_PREPARATION_SUBMITTED_ONCE" in lines
PY

echo "=== FROZEN SEQUENCE 53 INSPECTION EVIDENCE ==="
[[ -f "${RESULT_53}" && ! -L "${RESULT_53}" ]] || fail "sequence 53 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_53}")" -eq 1 ]] || fail "sequence 53 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_53}")" -eq "${RESULT_53_SIZE}" ]] || fail "sequence 53 result size changed"
[[ "$(sha256sum "${RESULT_53}" | awk '{print $1}')" = "${RESULT_53_SHA}" ]] || fail "sequence 53 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_53.txt)" = "${RESULT_53_COMMIT}" ]] || fail "sequence 53 result commit changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_53_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_53.txt" ]] || fail "sequence 53 result commit surface changed"
git merge-base --is-ancestor "${INSPECTION_53_COMMIT}" "${RESULT_53_COMMIT}" || fail "sequence 53 command is not an ancestor of its result"
[[ "$(git show "${INSPECTION_53_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${INSPECTION_53_COMMAND_SHA}" ]] || fail "sequence 53 inspection command hash changed"

"${PYTHON}" -B - "${RESULT_53}" "${JOB_ID}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=53"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=1"
assert lines[-1].startswith("### finished=")
assert any(line.startswith(f"{job_id}|tukf09-455-v2r4-prepare|hgpu8|COMPLETED|0:0|") for line in lines)
assert "STDERR_SIZE=0" in lines
assert "STDERR_SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" in lines
assert "STDOUT_LAST_LINE=TUKF09_455_HPC_PREPARATION_PROBE_COMPLETED" in lines
assert "=== STRICT PREPARATION ARTIFACT GATES ===" in lines
assert "KeyError: 'data_file_count'" in lines
assert not any(line.startswith("FATAL:") for line in lines)
PY

echo "=== FROZEN SEQUENCE 54 INSPECTION EVIDENCE ==="
[[ -f "${RESULT_54}" && ! -L "${RESULT_54}" ]] || fail "sequence 54 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_54}")" -eq 1 ]] || fail "sequence 54 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_54}")" -eq "${RESULT_54_SIZE}" ]] || fail "sequence 54 result size changed"
[[ "$(sha256sum "${RESULT_54}" | awk '{print $1}')" = "${RESULT_54_SHA}" ]] || fail "sequence 54 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_54.txt)" = "${RESULT_54_COMMIT}" ]] || fail "sequence 54 result commit changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_54_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_54.txt" ]] || fail "sequence 54 result commit surface changed"
git merge-base --is-ancestor "${INSPECTION_54_COMMIT}" "${RESULT_54_COMMIT}" || fail "sequence 54 command is not an ancestor of its result"
[[ "$(git show "${INSPECTION_54_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${INSPECTION_54_COMMAND_SHA}" ]] || fail "sequence 54 inspection command hash changed"

"${PYTHON}" -B - "${RESULT_54}" "${JOB_ID}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=54"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=1"
assert lines[-1].startswith("### finished=")
assert any(line.startswith(f"{job_id}|tukf09-455-v2r4-prepare|hgpu8|COMPLETED|0:0|") for line in lines)
assert "STDERR_SIZE=0" in lines
assert "STDOUT_LAST_LINE=TUKF09_455_HPC_PREPARATION_PROBE_COMPLETED" in lines
assert "=== STRICT PREPARATION ARTIFACT GATES ===" in lines
assert '  File "<stdin>", line 107, in <module>' in lines
assert "AssertionError" in lines
assert not any(line.startswith("FATAL:") for line in lines)
PY

echo "=== FROZEN PREPARATION JOB RECORD ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status" "${SUBMISSION_LOCK}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing, linked, or irregular: ${item}"
done
[[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "preparation job id record missing, linked, or irregular"
[[ "$(stat -c '%h' "${JOB_ID_FILE}")" -eq 1 ]] || fail "preparation job id record hard-link count changed"
[[ "$(stat -c '%a' "${JOB_ID_FILE}")" = "444" ]] || fail "preparation job id record mode changed"
[[ "$(tr -d '\r\n' < "${JOB_ID_FILE}")" = "${JOB_ID}" ]] || fail "preparation job id record mismatch"

echo "=== SLURM STATE ==="
sacct_output=$(sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,NodeList,Elapsed,Start,End 2>&1) || fail "sacct failed: ${sacct_output}"
printf '%s\n' "${sacct_output}"
job_row=$(printf '%s\n' "${sacct_output}" | awk -F'|' -v id="${JOB_ID}" '$1==id {print; found=1} END {exit(found ? 0 : 1)}') || fail "exact preparation job row missing"
state=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $4}')
exit_code=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $5}')
recorded_name=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $2}')
[[ "${recorded_name}" = "${JOB_NAME}" ]] || fail "preparation job name mismatch"
squeue -j "${JOB_ID}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true

echo "=== FORMAL EVALUATION HOLD ==="
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done
for item in "${ROOT}/status/hpc_technical_admission.json" "${ROOT}/status/training_submission.lock" "${ROOT}/status/training_job_id.txt"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "technical admission or training evidence exists prematurely: ${item}"
done

case "${state}" in
  PENDING|RUNNING|CONFIGURING|COMPLETING)
    echo "TUKF09_455_A800_EXCLUSIVE_V2R4_PREPARATION_NOT_TERMINAL state=${state} exit_code=${exit_code}"
    exit 0
    ;;
  COMPLETED)
    [[ "${exit_code}" = "0:0" ]] || fail "completed preparation job has nonzero exit code: ${exit_code}"
    ;;
  *)
    echo "=== PRESERVED TERMINAL NONPASS EVIDENCE ==="
    for log in "${STDOUT}" "${STDERR}"; do
      if [[ -f "${log}" && ! -L "${log}" ]]; then
        echo "LOG=${log} SIZE=$(stat -c '%s' "${log}") SHA256=$(sha256sum "${log}" | awk '{print $1}')"
        tail -c 20000 "${log}"
      fi
    done
    for item in "${PREPARATION_FAILED}" "${ROOT}/runtime_v2r4.pending.${JOB_ID}" "${RUNTIME_ROOT}" "${INITIAL_BUNDLE}" "${STAGED_MANIFEST}" "${PREPARATION_PROBE}" "${STAGED_ROOT}" "${FILTER_SEAL}"; do
      if [[ -e "${item}" || -L "${item}" ]]; then
        stat -c 'PRESERVED=%F|%s|%h|%n' "${item}" || true
        if [[ -f "${item}" && ! -L "${item}" ]]; then
          echo "PRESERVED_SHA256=$(sha256sum "${item}" | awk '{print $1}')"
        fi
      fi
    done
    echo "TUKF09_455_A800_EXCLUSIVE_V2R4_PREPARATION_TERMINAL_NONPASS state=${state} exit_code=${exit_code}"
    exit 0
    ;;
esac

echo "=== TERMINAL LOG EVIDENCE ==="
for item in "${STDOUT}" "${STDERR}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "terminal preparation log missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "terminal preparation log hard-link count changed: ${item}"
done
[[ ! -s "${STDERR}" ]] || fail "preparation Slurm standard error is not empty"
[[ "$(tail -n 1 "${STDOUT}")" = "TUKF09_455_HPC_PREPARATION_PROBE_COMPLETED" ]] || fail "preparation completion marker missing"
[[ ! -e "${PREPARATION_FAILED}" && ! -L "${PREPARATION_FAILED}" ]] || fail "preparation failure marker exists after completed job"
echo "STDOUT_SIZE=$(stat -c '%s' "${STDOUT}")"
echo "STDOUT_SHA256=$(sha256sum "${STDOUT}" | awk '{print $1}')"
echo "STDERR_SIZE=$(stat -c '%s' "${STDERR}")"
echo "STDERR_SHA256=$(sha256sum "${STDERR}" | awk '{print $1}')"
echo "STDOUT_LAST_LINE=$(tail -n 1 "${STDOUT}")"

echo "=== STRICT PREPARATION ARTIFACT GATES ==="
for item in "${RUNTIME_ROOT}" "${RUNTIME_ROOT}/pysite" "${RUNTIME_ROOT}/wheelhouse" "${STAGED_ROOT}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "prepared directory missing, linked, or irregular: ${item}"
done
for item in "${PRIVATE_MANIFEST}" "${INITIAL_BUNDLE}" "${STAGED_MANIFEST}" "${PREPARATION_PROBE}" "${FILTER_SEAL}" "${ROOT}/status/preparation.lock"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "prepared evidence missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "prepared evidence hard-link count changed: ${item}"
done
[[ ! -e "${ROOT}/runtime_v2r4.pending.${JOB_ID}" && ! -L "${ROOT}/runtime_v2r4.pending.${JOB_ID}" ]] || fail "runtime pending directory remains after successful job"
if compgen -G "${ROOT}/status/staged_training_sources.pending-*" >/dev/null; then
  fail "staged-data pending directory remains after successful job"
fi

"${PYTHON}" -B - "${PROJECT_ROOT}" "${ROOT}" "${JOB_ID}" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

project = Path(sys.argv[1])
root = Path(sys.argv[2])
job_id = sys.argv[3]
stage_path = project / "hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/stage_and_train.py"
spec = importlib.util.spec_from_file_location("tukf09_stage_v2r4_audit", stage_path)
assert spec is not None and spec.loader is not None
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)
config = stage.load_execution_config(project / "configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r4.json")

runtime = root / "runtime_v2r4"
private_path = runtime / "evidence/private_runtime_manifest.json"
initial_path = root / "status/initial_bundle_verification.json"
staged_path = root / "status/staged_training_sources.json"
probe_path = root / "status/preparation_probe.json"
filter_seal = project / "results/tukf09_455_basin_zero_validation_target_variance_revision_v1/control/filter_rebinding/independent/manifest.final.sha256.json"
filter_verifier_path = project / "scripts/verify_tukf09_455_filter_installation.py"

private = stage.verify_private_runtime_manifest(
    manifest_path=private_path,
    pysite=runtime / "pysite",
    wheelhouse=runtime / "wheelhouse",
    import_check=False,
)
initial = stage.read_json(initial_path, root=root, canonical=True)
staged = stage.read_json(staged_path, root=root, canonical=True)
probe = stage.read_json(probe_path, root=root, canonical=True)
stage._verify_payload_identity(initial, label="initial bundle verification")
stage._verify_payload_identity(staged, label="staged training sources")
stage._verify_payload_identity(probe, label="preparation probe")

assert initial["status"] == "STRICT_PRISTINE_A800_EXCLUSIVE_V2R4_BUNDLE_VERIFIED_BEFORE_RUNTIME_MUTATION"
assert initial["member_count"] == 2808
assert initial["admitted_executable_count"] == 30
assert initial["admitted_test_count"] == 12
assert type(initial["formal_evaluation_output_count"]) is int
assert initial["formal_evaluation_output_count"] == 0
assert initial["mutable_file_count_at_verification"] == 0
assert initial["mutable_directory_count_at_verification"] == 0
assert initial["scientific_contract_changed"] is False

assert staged["status"] == "STAGED_455_TRAINING_VALIDATION_SOURCE_FILES_EVALUATION_HOLD"
assert len(staged["ordered_basin_ids"]) == 455
assert staged["file_count"] == 911
assert len(staged["file_sha256"]) == 911
assert len(staged["file_size"]) == 911
for field in (
    "evaluation_array_reads",
    "evaluation_predictions",
    "evaluation_metrics",
    "evaluation_outputs",
):
    assert type(staged[field]) is int and staged[field] == 0
capsule = stage.verify_source_capsule_evidence(
    staged,
    config=config,
    label="staged training source manifest",
)
assert capsule["source_capsule_data_file_count"] == 911
assert capsule["source_capsule_evidence_file_count"] == 3
assert capsule["source_capsule_directory_count"] == 44
assert capsule["source_capsule_data_total_bytes"] == 464792200
assert capsule["source_capsule_data_identity_sha256"] == "dd238eebc1696f73f9eee7adf924913ff5a912c8f795f8998255e87408b760da"
records = {
    name: {"sha256": staged["file_sha256"][name], "size_bytes": staged["file_size"][name]}
    for name in staged["file_sha256"]
}
verified_stage = stage.verify_staged_training_sources(
    destination_root=project / "G:/github/pycharm/projects/neuralhydrology/data/camels_us",
    records=records,
)
assert verified_stage["file_count"] == 911
assert verified_stage["total_size_bytes"] == staged["total_size_bytes"]

assert private["status"] == "PRIVATE_RUNTIME_FROZEN_NOT_A_SCIENTIFIC_CONTRACT_CHANGE"
assert private["target_versions"] == {"numpy": "1.26.4", "psutil": "5.9.0", "torch": "2.2.2"}
assert private["private_dependency_closure_complete"] is True
assert private["shared_nh_final_modified"] is False
assert private["offline_input_manifest_sha256"] == "269daf813e7306815c549ae879f519d64b970fb014208e930848dd94ff819b2e"
assert private["offline_input_identity_sha256"] == "e77d74fd1e9103ed9e1fa6ee3bb5f18e905b38eb529dbecce029422296bf3835"
assert private["offline_input_total_file_count"] == 24
assert private["offline_input_total_bytes"] == 2817756909

assert probe["status"] == "HPC_A800_EXCLUSIVE_V2R4_PREPARED_FILTERS_455_NEURAL_0_OF_9_EVALUATION_HOLD"
assert probe["bundle_manifest_sha256"] == "97eccb8c689e1c1b22577ba8823a8fb0802a14f10db213f861c5b9e3b504bdc1"
assert probe["filter_unit_count"] == 455
assert probe["neural_model_unit_count"] == 0
for field in (
    "evaluation_array_reads",
    "evaluation_predictions",
    "evaluation_metrics",
    "evaluation_outputs",
):
    assert type(probe[field]) is int and probe[field] == 0
assert probe["scientific_contract_changed"] is False
assert probe["initial_bundle_verification_sha256"] == stage.sha256_file(initial_path)
assert probe["initial_bundle_verification_identity_sha256"] == initial["identity_sha256"]
assert probe["private_runtime_manifest_sha256"] == stage.sha256_file(private_path)
assert probe["private_runtime_identity_sha256"] == private["identity_sha256"]
assert probe["staged_sources_manifest_sha256"] == stage.sha256_file(staged_path)
assert probe["staged_sources_identity_sha256"] == staged["identity_sha256"]
actual_remote_filter_seal_sha256 = stage.sha256_file(filter_seal)
probe_remote_filter_seal_sha256 = probe["remote_filter_installation_final_sha256"]
local_filter_seal_sha256 = config["scientific_identity"]["local_filter_installation_final_manifest"]["sha256"]
assert actual_remote_filter_seal_sha256 != probe_remote_filter_seal_sha256
assert local_filter_seal_sha256 == "b378ffbfde4d24ded8fbb42fdf10fef59eb04100c93879a41b4d538ae36f6ba0"
filter_spec = importlib.util.spec_from_file_location("tukf09_filter_verifier_v2r4_audit", filter_verifier_path)
assert filter_spec is not None and filter_spec.loader is not None
filter_verifier = importlib.util.module_from_spec(filter_spec)
filter_spec.loader.exec_module(filter_verifier)
filter_verification = filter_verifier.verify_filter_installation_independently(
    migration_root=project / "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/filter_migration_v1",
    results_root=project / "results/tukf09_455_basin_zero_validation_target_variance_revision_v1",
    training_admission_path=project / "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/training_admission/training_admission.json",
    authorize=True,
    publish=False,
)
assert filter_verification["status"] == "FILTER_REBINDING_INDEPENDENTLY_VERIFIED_EVALUATION_HOLD"
assert filter_verification["unit_count"] == 455
assert filter_verification["unit_file_count"] == 2730
assert filter_verification["new_filter_optimization_count"] == 0
assert filter_verification["evaluation_access_count"] == 0
runtime_identity = probe["runtime"]
assert runtime_identity["slurm_job_id"] == job_id
assert runtime_identity["cuda_available"] is True
assert runtime_identity["cuda_device_count"] == 1
assert runtime_identity["cuda_device_name"] == "NVIDIA A800-SXM4-80GB"
assert runtime_identity["cuda_compute_capability"] == [8, 0]
assert runtime_identity["torch_base_version"] == "2.2.2"
assert runtime_identity["numpy_version"] == "1.26.4"
assert runtime_identity["psutil_version"] == "5.9.0"
assert runtime_identity["exclusive_node_runtime_evidence_passed"] is True
assert runtime_identity["slurm_job_node_count"] == 1
assert runtime_identity["slurm_cpus_on_node"] == 64
assert runtime_identity["slurm_cpus_per_task"] == 4
assert runtime_identity["slurm_gpu_allocation_variable_present"] is True
assert runtime_identity["nvidia_gpu_uuid"] == runtime_identity["torch_process_gpu_uuid"]

print(json.dumps({
    "actual_remote_filter_seal_sha256": actual_remote_filter_seal_sha256,
    "filter_unit_count": probe["filter_unit_count"],
    "initial_bundle_sha256": stage.sha256_file(initial_path),
    "preparation_probe_identity_sha256": probe["identity_sha256"],
    "preparation_probe_sha256": stage.sha256_file(probe_path),
    "private_runtime_identity_sha256": private["identity_sha256"],
    "private_runtime_manifest_sha256": stage.sha256_file(private_path),
    "local_filter_seal_sha256": local_filter_seal_sha256,
    "probe_remote_filter_seal_sha256": probe_remote_filter_seal_sha256,
    "remote_filter_seal_matches_probe": actual_remote_filter_seal_sha256 == probe_remote_filter_seal_sha256,
    "remote_filter_verification_status": filter_verification["status"],
    "staged_file_count": staged["file_count"],
    "staged_sources_identity_sha256": staged["identity_sha256"],
    "staged_sources_manifest_sha256": stage.sha256_file(staged_path),
}, sort_keys=True))
PY

echo "TUKF09_455_A800_EXCLUSIVE_V2R4_FILTER_SEAL_DRIFT_DIAGNOSED_ADMISSION_NOT_CREATED"
