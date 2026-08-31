#!/bin/bash
# Deploy the immutable A800-exclusive v2r1 transport payload into a new unique root.
# This command performs deployment and strict verification only. It submits no job.
set -eo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901
FAILED_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831
FAILED_JOB_ID=217149
FAILED_STDOUT_SHA=37cf0cb26683b2a97c6484d52c2c90f0a5bb10356cfd097a0d599e7999a9b8ab
FAILED_STDERR_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
FAILED_INITIAL_VERIFICATION_SHA=b1b4c0f39187cb6c46cf4234f7da4131b33f2ffa35c523abf02eab6fdf38d0b9
MAILBOX_ROOT="$(pwd -P)"
PAYLOAD="${MAILBOX_ROOT}/payload/kalmannet-tukf09-455/a800-exclusive-v2r1"
ARCHIVE_NAME=tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r1_formal_training.tar.gz
BUILDER_NAME=build_tukf09_455_a800_exclusive_hpc_bundle_v2r1.py
ARCHIVE_SHA=d15ec97d9297cee003314a5697269b4cab8e55a91a78d7fda628729edd7146ea
ARCHIVE_SIZE=9893461
OUTER_SHA=e3b91795f86bfaac9163f52c8ca0d3a1bb301830e7f33623ed9de9c3aaa9b16d
BUILDER_SHA=b570841f2df32e3bd247e93e876a24a4d648c44f50a41680657ee77ab7dc05ec
INTERNAL_MANIFEST_SHA=ca7bc5b7bdd9a451d691130c6881cd146c3d89d2ef01385237faac0f91c46ad4
SEMANTICS_PROBE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_a800_exclusive_semantics_probe_v1_20260831_01a055e6
SEMANTICS_PROBE_JOB_ID=217122
SEMANTICS_PROBE_JSON_SHA=ba5f627b18369e634a558ec9f1edb8cd511464184e5ff33e7bff6acceabefc86

# Freeze the failed v2 preparation evidence. Nothing below writes to FAILED_ROOT.
test -d "${FAILED_ROOT}"
test ! -L "${FAILED_ROOT}"
test -f "${FAILED_ROOT}/status/initial_bundle_verification.json"
test ! -L "${FAILED_ROOT}/status/initial_bundle_verification.json"
test "$(sha256sum "${FAILED_ROOT}/status/initial_bundle_verification.json" | awk '{print $1}')" = "${FAILED_INITIAL_VERIFICATION_SHA}"
test -d "${FAILED_ROOT}/runtime_v2.pending.${FAILED_JOB_ID}"
test ! -L "${FAILED_ROOT}/runtime_v2.pending.${FAILED_JOB_ID}"
test -f "${FAILED_ROOT}/runtime_v2.pending.${FAILED_JOB_ID}/evidence/pip-stdout.log"
test -f "${FAILED_ROOT}/runtime_v2.pending.${FAILED_JOB_ID}/evidence/pip-stderr.log"
test "$(sha256sum "${FAILED_ROOT}/runtime_v2.pending.${FAILED_JOB_ID}/evidence/pip-stdout.log" | awk '{print $1}')" = "${FAILED_STDOUT_SHA}"
test "$(sha256sum "${FAILED_ROOT}/runtime_v2.pending.${FAILED_JOB_ID}/evidence/pip-stderr.log" | awk '{print $1}')" = "${FAILED_STDERR_SHA}"
sacct -j "${FAILED_JOB_ID}" -n -P --format=JobIDRaw,State,ExitCode | \
  awk -F'|' -v id="${FAILED_JOB_ID}" '$1==id && $2=="FAILED" && $3=="13:0" {ok=1} END {exit(ok ? 0 : 1)}'

# Retain the independently verified A800 exclusive-route semantics gate.
test -d "${SEMANTICS_PROBE_ROOT}"
test ! -L "${SEMANTICS_PROBE_ROOT}"
test -f "${SEMANTICS_PROBE_ROOT}/status/allocation_probe.json"
test ! -L "${SEMANTICS_PROBE_ROOT}/status/allocation_probe.json"
test "$(stat -c '%h' "${SEMANTICS_PROBE_ROOT}/status/allocation_probe.json")" -eq 1
test "$(sha256sum "${SEMANTICS_PROBE_ROOT}/status/allocation_probe.json" | awk '{print $1}')" = "${SEMANTICS_PROBE_JSON_SHA}"
test "$(tr -d '\r\n' < "${SEMANTICS_PROBE_ROOT}/status/submitted_job_id.txt")" = "${SEMANTICS_PROBE_JOB_ID}"
sacct -j "${SEMANTICS_PROBE_JOB_ID}" -n -P --format=JobIDRaw,State,ExitCode | \
  awk -F'|' -v id="${SEMANTICS_PROBE_JOB_ID}" '$1==id && $2=="COMPLETED" && $3=="0:0" {ok=1} END {exit(ok ? 0 : 1)}'

# Bind the mailbox payload before creating the remote root.
test -d "${PAYLOAD}"
test ! -L "${PAYLOAD}"
test "$(find "${PAYLOAD}" -mindepth 1 -maxdepth 1 | wc -l)" -eq 3
for name in "${ARCHIVE_NAME}" bundle_manifest.sha256.json "${BUILDER_NAME}"; do
  test -f "${PAYLOAD}/${name}"
  test ! -L "${PAYLOAD}/${name}"
  test "$(stat -c '%h' "${PAYLOAD}/${name}")" -eq 1
done
test "$(stat -c '%s' "${PAYLOAD}/${ARCHIVE_NAME}")" -eq "${ARCHIVE_SIZE}"
test "$(sha256sum "${PAYLOAD}/${ARCHIVE_NAME}" | awk '{print $1}')" = "${ARCHIVE_SHA}"
test "$(sha256sum "${PAYLOAD}/bundle_manifest.sha256.json" | awk '{print $1}')" = "${OUTER_SHA}"
test "$(sha256sum "${PAYLOAD}/${BUILDER_NAME}" | awk '{print $1}')" = "${BUILDER_SHA}"

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || \
source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo "CONDA_FAILED" >&2; exit 62; }
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE
PYTHON="${CONDA_PREFIX}/bin/python"

"${PYTHON}" -B - "${PAYLOAD}/bundle_manifest.sha256.json" "${ARCHIVE_SHA}" "${ARCHIVE_SIZE}" "${BUILDER_SHA}" <<'PY'
import json
from pathlib import Path
import sys

outer = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
archive_sha = sys.argv[2]
archive_size = int(sys.argv[3])
builder_sha = sys.argv[4]
builder_member = "kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r1.py"
expected_members = {
    builder_member: builder_sha,
    "kalmannet/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r1.json": "35a0de2a9f04faf51351fbd6f928575b0c293dd5d90c05ddfab9e3a05995d33b",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/allocation_probe.slurm": "5dc332b67998b6a2fa3b5a37f3db40694ff21cea832ff61750a527f136a4597b",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/probe_gpu.slurm": "c46b65d3f7200284d3fad1896570a8c0ea3c86d17538530261a87b0acafad350",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/psutil-source.lock": "c021239b1cdeafff41591adec793c79820ad66ec5418dba2570ea8ff2ae60d68",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/runtime-binary.lock": "8bfc922ce4165eb7793f0b4f1afe9a185644858875af6a3bfd21992a23046d9f",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/stage_and_train.py": "15d0f92a7360d48c804853436475ec9a0d83fb356be2536aa0fd816b9c741621",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/submit_training_gpu.slurm": "e7083dd184a3ce4636b7b428a777de979d1e8eedf8371422c73d16ae43b49635",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/verify_result.py": "ae1900174a493cbde8a0bc12cb191d3c15f92cde4c0cd69fc25ea86adf48b78f",
}
assert outer["schema_version"] == "tukf09_455_a800_exclusive_training_hpc_archive_manifest_v2r1"
assert outer["archive_name"] == "tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r1_formal_training.tar.gz"
assert outer["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert outer["purpose"] == "formal_training_only_no_formal_evaluation"
assert outer["archive_sha256"] == archive_sha
assert outer["archive_size"] == archive_size
assert outer["member_count"] == 2807
assert outer["admitted_executable_count"] == 30
assert outer["admitted_test_count"] == 12
assert outer["artifact_file_count"] == 2751
assert outer["config_file_count"] == 6
assert outer["non_admitted_wrapper_count"] == 8
for member, expected_sha in expected_members.items():
    assert outer["member_sha256"][member] == expected_sha
assert outer["scientific_contract_sha256"] == "7710594dcc5cce7f087cb70492a6f827c3925a98ea7fa051d26c5ef1660304e1"
assert outer["preflight_final_manifest_sha256"] == "f7e0a3f0708d0498cbaeaa77a044687f20d017ffa316170cd4770fc920b144aa"
assert outer["filter_migration_final_manifest_sha256"] == "029521f6c35980ce40fb0afeb14e2734042734c73f6ed0a33a5c0040311c3eb5"
assert outer["training_admission"] == {
    "path": "kalmannet/artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/training_admission/training_admission.json",
    "record_sha256": "ca43f2ba9e35b47c76808da925508e75770bc00a37f2a89ba1dcf060017531b4",
    "sha256": "6ba3cdd742fc2bdf039c51afc75485c8292f0b999d7fe426cb2ccf69057c1b79",
}
assert outer["local_results_file_count"] == 0
assert outer["camels_raw_file_count"] == 0
assert outer["neural_checkpoint_count"] == 0
assert outer["formal_selection_output_count"] == 0
assert outer["formal_evaluation_output_count"] == 0
PY

"${PYTHON}" -B - "${SEMANTICS_PROBE_ROOT}/status/allocation_probe.json" <<'PY'
import json
from pathlib import Path
import sys

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert record["schema_version"] == "tukf09_455_a800_exclusive_semantics_probe_v1"
assert record["status"] == "PASS"
assert record["errors"] == []
assert record["hostname"] == "ngu201"
allocation = record["normalized_allocation"]
assert allocation["exclusive_node_runtime_evidence_passed"] is True
assert allocation["job_cpus_per_node"] == 64
assert allocation["cpu_repeat"] == 1
assert allocation["node_count"] == 1
assert allocation["slurm_gpu_identifier_source"] == "SLURM_JOB_GPUS"
assert allocation["slurm_selected_gpu_identifier"] == "0"
selected = record["nvidia_slurm_selected_gpu"]
assert selected["name"] == "NVIDIA A800-SXM4-80GB"
assert int(selected["memory_total_mib"]) == 81920
inventory = record["nvidia_smi_inventory"]
assert len(inventory) == 8
assert sorted(item["index"] for item in inventory) == list(range(8))
assert len({item["uuid"] for item in inventory}) == 8
assert all(item["name"] == "NVIDIA A800-SXM4-80GB" for item in inventory)
assert all(item["memory_total_mib"] == 81920 for item in inventory)
assert record["preexisting_compute_processes"] == []
pytorch = record["pytorch"]
assert pytorch["cuda_available"] is True
assert pytorch["visible_device_count"] == 1
assert len(pytorch["visible_devices"]) == 1
assert pytorch["visible_devices"][0]["name"] == "NVIDIA A800-SXM4-80GB"
assert pytorch["visible_devices"][0]["capability"] == [8, 0]
assert pytorch["current_process_gpu_uuid"] == selected["uuid"]
environment = record["slurm_environment"]
assert environment["SLURM_JOB_CPUS_PER_NODE"] in {"64", "64(x1)"}
assert environment["SLURM_CPUS_ON_NODE"] == "64"
assert environment["SLURM_CPUS_PER_TASK"] == "4"
assert environment["SLURM_JOB_GPUS"] == "0"
assert environment["CUDA_VISIBLE_DEVICES"] == "0"
print("TUKF09_455_A800_EXCLUSIVE_ROUTE_SEMANTICS_PROBE_VERIFIED")
PY

# The new technical revision must start in a root that does not already exist.
if [[ -e "${ROOT}" || -L "${ROOT}" ]]; then
  echo "REFUSING_EXISTING_REMOTE_ROOT=${ROOT}" >&2
  exit 61
fi
mkdir "${ROOT}"
mkdir "${ROOT}/incoming" "${ROOT}/logs" "${ROOT}/status"
cp --no-clobber "${PAYLOAD}/${ARCHIVE_NAME}" "${ROOT}/incoming/${ARCHIVE_NAME}"
cp --no-clobber "${PAYLOAD}/bundle_manifest.sha256.json" "${ROOT}/incoming/bundle_manifest.sha256.json"
cp --no-clobber "${PAYLOAD}/${BUILDER_NAME}" "${ROOT}/incoming/${BUILDER_NAME}"
for name in "${ARCHIVE_NAME}" bundle_manifest.sha256.json "${BUILDER_NAME}"; do
  test -f "${ROOT}/incoming/${name}"
  test ! -L "${ROOT}/incoming/${name}"
  test "$(stat -c '%h' "${ROOT}/incoming/${name}")" -eq 1
done
test "$(stat -c '%s' "${ROOT}/incoming/${ARCHIVE_NAME}")" -eq "${ARCHIVE_SIZE}"
test "$(sha256sum "${ROOT}/incoming/${ARCHIVE_NAME}" | awk '{print $1}')" = "${ARCHIVE_SHA}"
test "$(sha256sum "${ROOT}/incoming/bundle_manifest.sha256.json" | awk '{print $1}')" = "${OUTER_SHA}"
test "$(sha256sum "${ROOT}/incoming/${BUILDER_NAME}" | awk '{print $1}')" = "${BUILDER_SHA}"

"${PYTHON}" -B "${ROOT}/incoming/${BUILDER_NAME}" \
  --archive "${ROOT}/incoming/${ARCHIVE_NAME}" \
  --extract-to "${ROOT}/bundle" \
  > "${ROOT}/status/deployment_extract_verification.json"
"${PYTHON}" -B "${ROOT}/bundle/kalmannet/scripts/${BUILDER_NAME}" \
  --verify-extracted "${ROOT}/bundle" \
  > "${ROOT}/status/deployment_strict_verification.json"

"${PYTHON}" -B - "${ROOT}" "${ARCHIVE_SHA}" "${ARCHIVE_SIZE}" "${BUILDER_SHA}" "${INTERNAL_MANIFEST_SHA}" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
archive_sha = sys.argv[2]
archive_size = int(sys.argv[3])
builder_sha = sys.argv[4]
internal_manifest_sha = sys.argv[5]
outer = json.loads((root / "incoming/bundle_manifest.sha256.json").read_text(encoding="utf-8"))
extracted = json.loads((root / "status/deployment_extract_verification.json").read_text(encoding="utf-8"))
strict = json.loads((root / "status/deployment_strict_verification.json").read_text(encoding="utf-8"))
assert outer["archive_sha256"] == archive_sha
assert outer["archive_size"] == archive_size
assert outer["member_count"] == 2807
assert extracted["status"] == "TUKF09_455_A800_EXCLUSIVE_V2R1_HPC_BUNDLE_VERIFIED"
assert extracted["member_count"] == 2807
assert extracted["reused"] is False
assert strict["status"] == "TUKF09_455_A800_EXCLUSIVE_V2R1_HPC_BUNDLE_VERIFIED"
assert strict["member_count"] == 2807
assert strict["admitted_executable_count"] == 30
assert strict["admitted_test_count"] == 12
assert strict["artifact_file_count"] == 2751
assert strict["formal_evaluation_output_count"] == 0
builder = root / "bundle/kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r1.py"
manifest = root / "bundle/bundle_manifest.json"
assert builder.is_file() and not builder.is_symlink()
assert hashlib.sha256(builder.read_bytes()).hexdigest() == builder_sha
assert manifest.is_file() and not manifest.is_symlink()
assert hashlib.sha256(manifest.read_bytes()).hexdigest() == internal_manifest_sha
for forbidden in (
    root / "runtime_v2r1",
    root / "results",
    root / "staged",
    root / "status/allocation_probe.json",
    root / "status/preparation_probe.json",
    root / "status/hpc_technical_admission.json",
):
    assert not forbidden.exists() and not forbidden.is_symlink(), forbidden
summary = {
    "archive_sha256": archive_sha,
    "bundle_manifest_sha256": internal_manifest_sha,
    "failed_predecessor_job_id": 217149,
    "failed_predecessor_root": "/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831",
    "formal_evaluation_authorized": False,
    "member_count": strict["member_count"],
    "remote_root": str(root),
    "status": "A800_EXCLUSIVE_V2R1_DEPLOYED_STRICT_BUNDLE_VERIFIED_FORMAL_EVALUATION_HOLD",
}
summary_path = root / "status/deployment_summary.json"
with summary_path.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(summary, handle, ensure_ascii=True, indent=2, sort_keys=True)
    handle.write("\n")
print(json.dumps(summary, sort_keys=True))
PY

echo "TUKF09_455_A800_EXCLUSIVE_V2R1_DEPLOYMENT_COMPLETED"
