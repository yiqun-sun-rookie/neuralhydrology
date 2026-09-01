#!/bin/bash
# Freeze the passed sequence 68 read-only audit, repeat the strict gates, then
# create and independently verify only the v2r5 HPC technical admission.
# This command submits no job and keeps formal evaluation closed.
set -euo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
STAGED_ROOT="${PROJECT_ROOT}/G:/github/pycharm/projects/neuralhydrology/data/camels_us"
RUNTIME_ROOT="${ROOT}/runtime_v2r5"
PRIVATE_MANIFEST="${RUNTIME_ROOT}/evidence/private_runtime_manifest.json"
INITIAL_BUNDLE="${ROOT}/status/initial_bundle_verification.json"
STAGED_MANIFEST="${ROOT}/status/staged_training_sources.json"
PREPARATION_PROBE="${ROOT}/status/preparation_probe.json"
PREPARATION_FAILED="${ROOT}/status/PREPARATION_FAILED.json"
FILTER_SEAL="${RESULTS_ROOT}/control/filter_rebinding/independent/manifest.final.sha256.json"
ADMISSION="${ROOT}/status/hpc_technical_admission.json"
JOB_ID=217817
JOB_NAME=tukf09-455-v2r5-prepare
JOB_ID_FILE="${ROOT}/status/preparation_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/preparation_submission.lock"
STDOUT="${ROOT}/logs/prepare-${JOB_ID}.out"
STDOUT_SIZE=2465173
STDOUT_SHA=d3b9880c33868793bf61638912299a8ef3173e139fa9e669f2345189d88a4210
STDERR="${ROOT}/logs/prepare-${JOB_ID}.err"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
MAILBOX_ROOT="$(pwd -P)"
RESULT_66="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_66.txt"
RESULT_66_COMMIT=536d022bcace7a2e8d4b9b0fe40d58735b436e6f
RESULT_66_COMMAND_COMMIT=fc4126e00c9a456b330a3b9dc3a2584a2c2cdd68
RESULT_66_COMMAND_SHA=5fbf5877ae8cad8e20b8f06752ddbb93ec4957425e5e964fe1606336f02fd09b
RESULT_66_SIZE=913
RESULT_66_SHA=a83cd6f965fced3f390cb586144a6e446df0ad4bdbcf34bd9adc5e229fc84025
RESULT_67="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_67.txt"
RESULT_67_COMMIT=0ea97b080e3c49d61d668e70e562b14aeaf1a7bb
RESULT_67_COMMAND_COMMIT=1a28d50250ffa104b7798fe76c83772fcb52227e
RESULT_67_COMMAND_SHA=6d03ca93a82b351387a47a3b26c275427fdc7ec1dc521162e753a59ab4e5ef84
RESULT_67_SIZE=1680
RESULT_67_SHA=2b6e1bc9aa0e865624463be06a90c33cbde2485a94a7acbba9a12e40f5069f25
RESULT_68="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_68.txt"
RESULT_68_COMMIT=ec9a9ebea56b926fa9e8b5ebae56519fd53bfc6c
RESULT_68_COMMAND_COMMIT=6c22af09600c99567504039ea4e131f65f58bb07
RESULT_68_COMMAND_SHA=6239f5e9f6704656eb9ce063ae053b3ee63c853f4629b4ca42cf4273a7c2dd19
RESULT_68_SIZE=2756
RESULT_68_SHA=450142fab24b9c06c802dcbd30e46a6fac01f9faa43713743022a9cfb2fb57c4
BUILDER="${PROJECT_ROOT}/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r5.py"
STAGE_TOOL="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/stage_and_train.py"
CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r5.json"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${PROJECT_ROOT}"

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN SEQUENCE 66 SUBMISSION EVIDENCE ==="
[[ -x "${PYTHON}" ]] || fail "shared Python launcher missing"
[[ -f "${RESULT_66}" && ! -L "${RESULT_66}" ]] || fail "sequence 66 result missing or linked"
[[ "$(stat -c '%h' "${RESULT_66}")" -eq 1 ]] || fail "sequence 66 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_66}")" -eq "${RESULT_66_SIZE}" ]] || fail "sequence 66 result size changed"
[[ "$(sha256sum "${RESULT_66}" | awk '{print $1}')" = "${RESULT_66_SHA}" ]] || fail "sequence 66 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_66.txt)" = "${RESULT_66_COMMIT}" ]] || fail "sequence 66 result commit changed"
git merge-base --is-ancestor "${RESULT_66_COMMAND_COMMIT}" "${RESULT_66_COMMIT}" || fail "sequence 66 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_66_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${RESULT_66_COMMAND_COMMIT}" ]] || fail "sequence 66 command was not the last channel command before its result"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_66_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_66.txt" ]] || fail "sequence 66 result commit surface changed"
[[ "$(git show "${RESULT_66_COMMAND_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${RESULT_66_COMMAND_SHA}" ]] || fail "sequence 66 command hash changed"

"${PYTHON}" -B - "${RESULT_66}" "${JOB_ID}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=66"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert lines.count(f"Submitted batch job {job_id}") == 1
assert f"PREPARATION_JOB_ID={job_id}" in lines
assert "TUKF09_455_A800_EXCLUSIVE_V2R5_OFFLINE_PREPARATION_SUBMITTED_ONCE_FORMAL_EVALUATION_HOLD" in lines
assert not any(line.startswith("FATAL:") for line in lines)
PY

echo "=== FROZEN SEQUENCE 67 READ-ONLY AUDIT-LAYER FAILURE EVIDENCE ==="
[[ -f "${RESULT_67}" && ! -L "${RESULT_67}" ]] || fail "sequence 67 result missing or linked"
[[ "$(stat -c '%h' "${RESULT_67}")" -eq 1 ]] || fail "sequence 67 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_67}")" -eq "${RESULT_67_SIZE}" ]] || fail "sequence 67 result size changed"
[[ "$(sha256sum "${RESULT_67}" | awk '{print $1}')" = "${RESULT_67_SHA}" ]] || fail "sequence 67 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_67.txt)" = "${RESULT_67_COMMIT}" ]] || fail "sequence 67 result commit changed"
git merge-base --is-ancestor "${RESULT_67_COMMAND_COMMIT}" "${RESULT_67_COMMIT}" || fail "sequence 67 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_67_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${RESULT_67_COMMAND_COMMIT}" ]] || fail "sequence 67 command was not the last channel command before its result"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_67_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_67.txt" ]] || fail "sequence 67 result commit surface changed"
[[ "$(git show "${RESULT_67_COMMAND_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${RESULT_67_COMMAND_SHA}" ]] || fail "sequence 67 command hash changed"

"${PYTHON}" -B - "${RESULT_67}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=67"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=1"
assert lines[-1].startswith("### finished=")
assert "=== REPAIRED RUNTIME BUNDLE VERIFICATION ===" in lines
assert '  "status": "TUKF09_455_A800_EXCLUSIVE_V2R5_HPC_RUNTIME_BUNDLE_VERIFIED"' in lines
assert "=== INDEPENDENT PREPARATION PAYLOAD AUDIT ===" in lines
assert "KeyError: 'hpc_identity'" in lines
assert not any(line.startswith("FATAL:") for line in lines)
assert "TUKF09_455_A800_EXCLUSIVE_V2R5_PREPARATION_COMPLETED_STRICTLY_VERIFIED_ADMISSION_NOT_CREATED_FORMAL_EVALUATION_HOLD" not in lines
PY

echo "=== FROZEN SEQUENCE 68 STRICT PREPARATION PASS EVIDENCE ==="
[[ -f "${RESULT_68}" && ! -L "${RESULT_68}" ]] || fail "sequence 68 result missing or linked"
[[ "$(stat -c '%h' "${RESULT_68}")" -eq 1 ]] || fail "sequence 68 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_68}")" -eq "${RESULT_68_SIZE}" ]] || fail "sequence 68 result size changed"
[[ "$(sha256sum "${RESULT_68}" | awk '{print $1}')" = "${RESULT_68_SHA}" ]] || fail "sequence 68 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_68.txt)" = "${RESULT_68_COMMIT}" ]] || fail "sequence 68 result commit changed"
git merge-base --is-ancestor "${RESULT_68_COMMAND_COMMIT}" "${RESULT_68_COMMIT}" || fail "sequence 68 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_68_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${RESULT_68_COMMAND_COMMIT}" ]] || fail "sequence 68 command was not the last channel command before its result"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_68_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_68.txt" ]] || fail "sequence 68 result commit surface changed"
[[ "$(git show "${RESULT_68_COMMAND_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${RESULT_68_COMMAND_SHA}" ]] || fail "sequence 68 command hash changed"

"${PYTHON}" -B - "${RESULT_68}" <<'PY'
from pathlib import Path
import json
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=68"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert "=== REPAIRED RUNTIME BUNDLE VERIFICATION ===" in lines
assert '  "status": "TUKF09_455_A800_EXCLUSIVE_V2R5_HPC_RUNTIME_BUNDLE_VERIFIED"' in lines
assert "=== INDEPENDENT PREPARATION PAYLOAD AUDIT ===" in lines
summary = next(json.loads(line) for line in lines if line.startswith('{"filter_unit_count"'))
assert summary["filter_unit_count"] == 455
assert summary["local_filter_seal_provenance_sha256"] == "b378ffbfde4d24ded8fbb42fdf10fef59eb04100c93879a41b4d538ae36f6ba0"
assert summary["remote_filter_seal_sha256"] == "7ecfa4d5a61f37a2fc40e75b9e1bbec4be6c39ba7b0b87ec8705bcca277faaa0"
assert summary["staged_file_count"] == 911
assert "TUKF09_455_A800_EXCLUSIVE_V2R5_PREPARATION_COMPLETED_STRICTLY_VERIFIED_AFTER_READ_ONLY_AUDIT_LAYER_FIX_ADMISSION_NOT_CREATED_FORMAL_EVALUATION_HOLD" in lines
assert not any(line.startswith("FATAL:") for line in lines)
PY

echo "=== FROZEN PREPARATION JOB RECORD ==="
for item in "${ROOT}" "${PROJECT_ROOT}" "${ROOT}/logs" "${ROOT}/status" "${SUBMISSION_LOCK}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required directory missing or linked: ${item}"
done
[[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]] || fail "preparation job id record missing or linked"
[[ "$(stat -c '%h' "${JOB_ID_FILE}")" -eq 1 ]] || fail "preparation job id record hard-link count changed"
[[ "$(stat -c '%a' "${JOB_ID_FILE}")" = "444" ]] || fail "preparation job id record mode changed"
[[ "$(tr -d '\r\n' < "${JOB_ID_FILE}")" = "${JOB_ID}" ]] || fail "preparation job id record mismatch"

echo "=== COMPLETED SLURM STATE ==="
sacct_output=$(sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,NodeList,Elapsed,Start,End 2>&1) || fail "sacct failed: ${sacct_output}"
printf '%s\n' "${sacct_output}"
job_row=$(printf '%s\n' "${sacct_output}" | awk -F'|' -v id="${JOB_ID}" '$1==id {print; found=1} END {exit(found ? 0 : 1)}') || fail "exact preparation job row missing"
state=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $4}')
exit_code=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $5}')
recorded_name=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $2}')
recorded_partition=$(printf '%s\n' "${job_row}" | awk -F'|' 'NR==1 {print $3}')
[[ "${recorded_name}" = "${JOB_NAME}" ]] || fail "preparation job name mismatch"
[[ "${recorded_partition}" = "hgpu8" ]] || fail "preparation partition mismatch"
[[ "${state}" = "COMPLETED" && "${exit_code}" = "0:0" ]] || fail "preparation job is not COMPLETED/0:0"

echo "=== FORMAL EVALUATION AND TRAINING HOLD ==="
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done
for item in "${ADMISSION}" "${ROOT}/status/training_submission.lock" "${ROOT}/status/training_job_id.txt"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "technical admission or training evidence exists prematurely: ${item}"
done

echo "=== TERMINAL LOG EVIDENCE ==="
for item in "${STDOUT}" "${STDERR}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "terminal preparation log missing or linked: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "terminal preparation log hard-link count changed: ${item}"
done
[[ "$(stat -c '%s' "${STDOUT}")" -eq "${STDOUT_SIZE}" ]] || fail "preparation standard output size changed"
[[ "$(sha256sum "${STDOUT}" | awk '{print $1}')" = "${STDOUT_SHA}" ]] || fail "preparation standard output hash changed"
[[ ! -s "${STDERR}" ]] || fail "preparation standard error is not empty"
[[ "$(sha256sum "${STDERR}" | awk '{print $1}')" = "${EMPTY_SHA}" ]] || fail "preparation standard error hash changed"
[[ "$(tail -n 1 "${STDOUT}")" = "TUKF09_455_HPC_PREPARATION_PROBE_COMPLETED" ]] || fail "preparation completion marker missing"
[[ ! -e "${PREPARATION_FAILED}" && ! -L "${PREPARATION_FAILED}" ]] || fail "preparation failure marker exists"
echo "STDOUT_SIZE=${STDOUT_SIZE}"
echo "STDOUT_SHA256=${STDOUT_SHA}"
echo "STDERR_SIZE=0"
echo "STDERR_SHA256=${EMPTY_SHA}"

echo "=== STRICT PREPARATION ARTIFACT GATES ==="
for item in "${RUNTIME_ROOT}" "${RUNTIME_ROOT}/pysite" "${RUNTIME_ROOT}/wheelhouse" "${STAGED_ROOT}"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "prepared directory missing or linked: ${item}"
done
for item in "${PRIVATE_MANIFEST}" "${INITIAL_BUNDLE}" "${STAGED_MANIFEST}" "${PREPARATION_PROBE}" "${FILTER_SEAL}" "${ROOT}/status/preparation.lock" "${BUILDER}" "${STAGE_TOOL}" "${CONFIG}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "prepared evidence missing or linked: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "prepared evidence hard-link count changed: ${item}"
done
if compgen -G "${ROOT}/runtime_v2r5.pending.*" >/dev/null; then
  fail "runtime pending directory remains after successful job"
fi
if compgen -G "${ROOT}/status/staged_training_sources.pending-*" >/dev/null; then
  fail "staged-data pending directory remains after successful job"
fi

echo "=== REPAIRED RUNTIME BUNDLE VERIFICATION ==="
"${PYTHON}" -B "${BUILDER}" --verify-runtime "${ROOT}/bundle"

echo "=== INDEPENDENT PREPARATION PAYLOAD AUDIT ==="
"${PYTHON}" -B - "${PROJECT_ROOT}" "${ROOT}" "${JOB_ID}" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

project = Path(sys.argv[1])
root = Path(sys.argv[2])
job_id = sys.argv[3]
stage_path = project / "hpc/tukf09_455_basin_revision_a800_exclusive_v2r5/stage_and_train.py"
spec = importlib.util.spec_from_file_location("tukf09_stage_v2r5_audit", stage_path)
assert spec is not None and spec.loader is not None
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)
config_path = project / "configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r5.json"
config = stage.load_execution_config(config_path)

runtime = root / "runtime_v2r5"
private_path = runtime / "evidence/private_runtime_manifest.json"
initial_path = root / "status/initial_bundle_verification.json"
staged_path = root / "status/staged_training_sources.json"
probe_path = root / "status/preparation_probe.json"
filter_seal = project / "results/tukf09_455_basin_zero_validation_target_variance_revision_v1/control/filter_rebinding/independent/manifest.final.sha256.json"

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

assert config["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert config["technical_retry"]["revision"] == "v2r5"
assert config["scientific_identity"]["ordered_basin_count"] == 455
assert config["scientific_identity"]["excluded_basins"] == ["08202700"]
assert config["scientific_identity"]["local_filter_installation_final_manifest"]["sha256"] == "b378ffbfde4d24ded8fbb42fdf10fef59eb04100c93879a41b4d538ae36f6ba0"
assert config["execution_route"]["formal_evaluation_access"] is False

assert initial["status"] == "STRICT_PRISTINE_A800_EXCLUSIVE_V2R5_BUNDLE_VERIFIED_BEFORE_RUNTIME_MUTATION"
assert initial["member_count"] == 2808
assert initial["admitted_executable_count"] == 30
assert initial["admitted_test_count"] == 12
assert initial["formal_evaluation_output_count"] == 0
assert initial["mutable_file_count_at_verification"] == 0
assert initial["mutable_directory_count_at_verification"] == 0
assert initial["scientific_contract_changed"] is False

assert staged["status"] == "STAGED_455_TRAINING_VALIDATION_SOURCE_FILES_EVALUATION_HOLD"
assert len(staged["ordered_basin_ids"]) == 455
assert staged["file_count"] == 911
assert len(staged["file_sha256"]) == 911
assert len(staged["file_size"]) == 911
for field in ("evaluation_array_reads", "evaluation_predictions", "evaluation_metrics", "evaluation_outputs"):
    assert type(staged[field]) is int and staged[field] == 0
capsule = stage.verify_source_capsule_evidence(staged, config=config, label="staged training source manifest")
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
assert private["offline_input_manifest_sha256"] == "2507f0ea14c4880c4aad9a3ccd5a2e6e1c5e5be1ee18bd0093c52d5db85acf82"
assert private["offline_input_identity_sha256"] == "28f30e3ff15639e2d68fcc683deb5a242675f3597541d0f928a5ec37a40aae53"
assert private["offline_input_total_file_count"] == 24
assert private["offline_input_total_bytes"] == 2817756909

assert probe["status"] == "HPC_A800_EXCLUSIVE_V2R5_PREPARED_FILTERS_455_NEURAL_0_OF_9_EVALUATION_HOLD"
assert probe["bundle_manifest_sha256"] == "f7c18d0a95849ee1d7d0a64c7a8724b6cf1fc0b84967503bd7ec1b484b239e76"
assert probe["filter_unit_count"] == 455
assert probe["neural_model_unit_count"] == 0
for field in ("evaluation_array_reads", "evaluation_predictions", "evaluation_metrics", "evaluation_outputs"):
    assert type(probe[field]) is int and probe[field] == 0
assert probe["scientific_contract_changed"] is False
assert probe["initial_bundle_verification_sha256"] == stage.sha256_file(initial_path) == "8bd135e5b5b0cc61fe328aaba1afe3521f3293e629697d32a1c2234794d4f27f"
assert probe["initial_bundle_verification_identity_sha256"] == initial["identity_sha256"] == "f12f515270c0bda53b2a8ee5687987f407dd60ad67a3358f44b239a450b46514"
assert probe["private_runtime_manifest_sha256"] == stage.sha256_file(private_path) == "4207579e6a7af408da933ff1075d537186878cbbcb4b0f17e8778b6a47a98aee"
assert probe["private_runtime_identity_sha256"] == private["identity_sha256"] == "08083e4f7bafdb9fa32e3982f70fe47ff5952fc188964032a5df4633210b024a"
assert probe["staged_sources_manifest_sha256"] == stage.sha256_file(staged_path) == "fecab69d1ce6fa0b23c2f5b22203a31d87b1c53264fe41a2092c8a2f87e5c0b9"
assert probe["staged_sources_identity_sha256"] == staged["identity_sha256"] == "75cdddfde1b15181dbcace5357fc540781005bfb3d2ff7777a204ff1c51fed8e"
assert probe["remote_filter_installation_final_sha256"] == stage.sha256_file(filter_seal) == "7ecfa4d5a61f37a2fc40e75b9e1bbec4be6c39ba7b0b87ec8705bcca277faaa0"
assert stage.sha256_file(filter_seal) != config["scientific_identity"]["local_filter_installation_final_manifest"]["sha256"]

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
    "filter_unit_count": probe["filter_unit_count"],
    "initial_bundle_sha256": stage.sha256_file(initial_path),
    "local_filter_seal_provenance_sha256": config["scientific_identity"]["local_filter_installation_final_manifest"]["sha256"],
    "preparation_probe_identity_sha256": probe["identity_sha256"],
    "preparation_probe_sha256": stage.sha256_file(probe_path),
    "private_runtime_identity_sha256": private["identity_sha256"],
    "private_runtime_manifest_sha256": stage.sha256_file(private_path),
    "remote_filter_seal_sha256": stage.sha256_file(filter_seal),
    "staged_file_count": staged["file_count"],
    "staged_sources_identity_sha256": staged["identity_sha256"],
    "staged_sources_manifest_sha256": stage.sha256_file(staged_path),
}, sort_keys=True))
PY

echo "TUKF09_455_A800_EXCLUSIVE_V2R5_PREPARATION_COMPLETED_STRICTLY_VERIFIED_AFTER_READ_ONLY_AUDIT_LAYER_FIX_ADMISSION_NOT_CREATED_FORMAL_EVALUATION_HOLD"

echo "=== CREATE EXCLUSIVE HPC TECHNICAL ADMISSION ONLY ==="
"${PYTHON}" -B "${STAGE_TOOL}" admit \
  --project-root "${PROJECT_ROOT}" \
  --probe "${PREPARATION_PROBE}" \
  --private-manifest "${PRIVATE_MANIFEST}" \
  --output "${ADMISSION}" \
  --authorize-hpc-technical-execution

[[ -f "${ADMISSION}" && ! -L "${ADMISSION}" ]] || fail "HPC technical admission was not created as a regular unlinked file"
[[ "$(stat -c '%h' "${ADMISSION}")" -eq 1 ]] || fail "HPC technical admission hard-link count changed"
[[ ! -e "${ROOT}/status/training_submission.lock" && ! -L "${ROOT}/status/training_submission.lock" ]] || fail "training submission lock exists prematurely"
[[ ! -e "${ROOT}/status/training_job_id.txt" && ! -L "${ROOT}/status/training_job_id.txt" ]] || fail "training job id exists prematurely"

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
spec = importlib.util.spec_from_file_location("tukf09_stage_v2r5_admission_audit", stage_path)
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
science = config["scientific_identity"]
assert admission["status"] == "HPC_A800_EXCLUSIVE_V2R5_TECHNICAL_EXECUTION_ADMITTED_FORMAL_EVALUATION_HOLD"
assert admission["scientific_contract_sha256"] == "7710594dcc5cce7f087cb70492a6f827c3925a98ea7fa051d26c5ef1660304e1"
assert admission["original_training_admission_file_sha256"] == "6ba3cdd742fc2bdf039c51afc75485c8292f0b999d7fe426cb2ccf69057c1b79"
assert admission["original_training_admission_record_sha256"] == "ca43f2ba9e35b47c76808da925508e75770bc00a37f2a89ba1dcf060017531b4"
assert admission["local_filter_installation_final_sha256"] == "b378ffbfde4d24ded8fbb42fdf10fef59eb04100c93879a41b4d538ae36f6ba0"
assert admission["remote_filter_installation_final_sha256"] == "7ecfa4d5a61f37a2fc40e75b9e1bbec4be6c39ba7b0b87ec8705bcca277faaa0"
assert admission["bundle_manifest_sha256"] == "f7c18d0a95849ee1d7d0a64c7a8724b6cf1fc0b84967503bd7ec1b484b239e76"
assert admission["initial_bundle_verification_sha256"] == "8bd135e5b5b0cc61fe328aaba1afe3521f3293e629697d32a1c2234794d4f27f"
assert admission["initial_bundle_verification_identity_sha256"] == "f12f515270c0bda53b2a8ee5687987f407dd60ad67a3358f44b239a450b46514"
assert admission["private_runtime_manifest_sha256"] == "4207579e6a7af408da933ff1075d537186878cbbcb4b0f17e8778b6a47a98aee"
assert admission["private_runtime_identity_sha256"] == "08083e4f7bafdb9fa32e3982f70fe47ff5952fc188964032a5df4633210b024a"
assert admission["offline_input_manifest_sha256"] == "2507f0ea14c4880c4aad9a3ccd5a2e6e1c5e5be1ee18bd0093c52d5db85acf82"
assert admission["offline_input_identity_sha256"] == "28f30e3ff15639e2d68fcc683deb5a242675f3597541d0f928a5ec37a40aae53"
assert admission["staged_sources_manifest_sha256"] == "fecab69d1ce6fa0b23c2f5b22203a31d87b1c53264fe41a2092c8a2f87e5c0b9"
assert admission["staged_sources_identity_sha256"] == "75cdddfde1b15181dbcace5357fc540781005bfb3d2ff7777a204ff1c51fed8e"
assert admission["preparation_probe_sha256"] == "59007f5d207f6dd5d9a1225f11d817fd3aabf04ff1690511705fe4546c4222fe"
assert admission["preparation_probe_identity_sha256"] == "a4d8c035a17640472d389796fecc84d2a4e194236551c37b59f280457920c4da"
assert admission["ordered_basin_count"] == 455
assert admission["neural_model_order"] == [f"lead_{lead}_seed_{seed}" for lead in (1, 2, 3) for seed in (0, 1, 2)]
assert admission["neural_model_parallelism"] == 1
assert admission["exclusive_node_required"] is True
assert admission["exclusive_node_runtime_evidence_passed"] is True
assert admission["formal_evaluation_authorized"] is False
assert admission["scientific_contract_changed"] is False
assert admission["original_training_admission_changed"] is False
assert admission["bitwise_equivalence_to_rtx3090_claimed"] is False
assert verified["identity_sha256"] == admission["identity_sha256"]
assert science["formal_training_execution"]["sha256"] == "0daf464f6bb1cfc11f04806b7caf5195ea42c3aef8187d8248474993ca108319"
print(json.dumps({
    "admission_identity_sha256": admission["identity_sha256"],
    "admission_sha256": stage.sha256_file(admission_path),
    "evaluation_array_reads": admission["evaluation_array_reads"],
    "evaluation_metrics": admission["evaluation_metrics"],
    "evaluation_outputs": admission["evaluation_outputs"],
    "evaluation_predictions": admission["evaluation_predictions"],
    "formal_evaluation_authorized": admission["formal_evaluation_authorized"],
    "neural_model_unit_count": len(admission["neural_model_order"]),
    "ordered_basin_count": admission["ordered_basin_count"],
    "status": admission["status"],
}, sort_keys=True))
PY

for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output appeared after admission: ${name}"
done
echo "ADMISSION_SIZE=$(stat -c '%s' "${ADMISSION}")"
echo "ADMISSION_SHA256=$(sha256sum "${ADMISSION}" | awk '{print $1}')"
echo "TUKF09_455_A800_EXCLUSIVE_V2R5_TECHNICAL_ADMISSION_CREATED_AND_VERIFIED_TRAINING_NOT_SUBMITTED_FORMAL_EVALUATION_HOLD"
