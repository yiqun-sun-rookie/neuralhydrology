#!/bin/bash
# Deploy the immutable A800-exclusive v2r2 transport payload into a new root.
# This command performs deployment and strict verification only. It submits no
# job, downloads no runtime input, starts no training, and runs no evaluation.
set -eo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r2_20260901
V2R1_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901
V2R1_JOB_ID=217163
V2R1_INITIAL_SHA=e1439af9226a3e94d7b8951e4f471e8c678990e3fbeb366c2e919cf9a3eae6b7
V2R1_JOB_STDOUT_SHA=3e5abfb0698e75b0d9f5c28c3bd98102384ad02c4ddd8386624443a8a6e8ec93
V2R1_JOB_STDERR_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
V2R1_PIP_STDOUT_SHA=f2b4b652eb10ebbf157a9d08a1871328059ced1aa941a8a7d41e14de9ce5be84
V2R1_PIP_STDERR_SHA=f9e8fe66ce1f3834235bba544f558c7cf0e45ac077dda75e119a97f0311dc71c
V2_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831
V2_JOB_ID=217149
V2_INITIAL_SHA=b1b4c0f39187cb6c46cf4234f7da4131b33f2ffa35c523abf02eab6fdf38d0b9
V2_PIP_STDOUT_SHA=37cf0cb26683b2a97c6484d52c2c90f0a5bb10356cfd097a0d599e7999a9b8ab
V2_PIP_STDERR_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
PRIOR_ALLOCATION_JOB_ID=217162
PRIOR_ALLOCATION_STDOUT_SHA=8004a5be9c9f31b664fb15c387dd22cf9dc68dc79d1ec12c31ae398a1af55e5c
MAILBOX_ROOT="$(pwd -P)"
PAYLOAD="${MAILBOX_ROOT}/payload/kalmannet-tukf09-455/a800-exclusive-v2r2"
ARCHIVE_NAME=tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r2_formal_training.tar.gz
BUILDER_NAME=build_tukf09_455_a800_exclusive_hpc_bundle_v2r2.py
ARCHIVE_SHA=479f1cb5dff88b794065f236440c329a589eda73364c323f5e60a5a9cc6f7776
ARCHIVE_SIZE=9902017
OUTER_SHA=640a534523ce2f59f411f28f78b4e671bc5df2dbb43df37b0ec227d8d58dd8cc
BUILDER_SHA=4b99a80ba82d723c64c59cf19364c6b0021c2d760ead14e1fd80998f61787a30
INTERNAL_MANIFEST_SHA=2cdccd6e32451c3c7a1bd34ec0207a63423b7bb5388b5f68073f454e1624ea04
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

# Freeze both failed predecessors. Nothing below writes to either root.
test -d "${V2R1_ROOT}"
test ! -L "${V2R1_ROOT}"
test "$(sha256sum "${V2R1_ROOT}/status/initial_bundle_verification.json" | awk '{print $1}')" = "${V2R1_INITIAL_SHA}"
test "$(sha256sum "${V2R1_ROOT}/logs/prepare-${V2R1_JOB_ID}.out" | awk '{print $1}')" = "${V2R1_JOB_STDOUT_SHA}"
test "$(sha256sum "${V2R1_ROOT}/logs/prepare-${V2R1_JOB_ID}.err" | awk '{print $1}')" = "${V2R1_JOB_STDERR_SHA}"
test -d "${V2R1_ROOT}/runtime_v2r1.pending.${V2R1_JOB_ID}"
test ! -L "${V2R1_ROOT}/runtime_v2r1.pending.${V2R1_JOB_ID}"
test "$(sha256sum "${V2R1_ROOT}/runtime_v2r1.pending.${V2R1_JOB_ID}/evidence/pip-stdout.log" | awk '{print $1}')" = "${V2R1_PIP_STDOUT_SHA}"
test "$(sha256sum "${V2R1_ROOT}/runtime_v2r1.pending.${V2R1_JOB_ID}/evidence/pip-stderr.log" | awk '{print $1}')" = "${V2R1_PIP_STDERR_SHA}"
sacct -j "${V2R1_JOB_ID}" -n -P --format=JobIDRaw,State,ExitCode | \
  awk -F'|' -v id="${V2R1_JOB_ID}" '$1==id && $2=="FAILED" && $3=="2:0" {ok=1} END {exit(ok ? 0 : 1)}'
for absent in \
  "${V2R1_ROOT}/runtime_v2r1" \
  "${V2R1_ROOT}/status/staged_training_sources.json" \
  "${V2R1_ROOT}/status/preparation_probe.json" \
  "${V2R1_ROOT}/status/hpc_technical_admission.json" \
  "${V2R1_ROOT}/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"; do
  test ! -e "${absent}"
  test ! -L "${absent}"
done

test -d "${V2_ROOT}"
test ! -L "${V2_ROOT}"
test "$(sha256sum "${V2_ROOT}/status/initial_bundle_verification.json" | awk '{print $1}')" = "${V2_INITIAL_SHA}"
test -d "${V2_ROOT}/runtime_v2.pending.${V2_JOB_ID}"
test ! -L "${V2_ROOT}/runtime_v2.pending.${V2_JOB_ID}"
test "$(sha256sum "${V2_ROOT}/runtime_v2.pending.${V2_JOB_ID}/evidence/pip-stdout.log" | awk '{print $1}')" = "${V2_PIP_STDOUT_SHA}"
test "$(sha256sum "${V2_ROOT}/runtime_v2.pending.${V2_JOB_ID}/evidence/pip-stderr.log" | awk '{print $1}')" = "${V2_PIP_STDERR_SHA}"
sacct -j "${V2_JOB_ID}" -n -P --format=JobIDRaw,State,ExitCode | \
  awk -F'|' -v id="${V2_JOB_ID}" '$1==id && $2=="FAILED" && $3=="13:0" {ok=1} END {exit(ok ? 0 : 1)}'

# Retain the exact package-native allocation success before deploying a new root.
sacct -j "${PRIOR_ALLOCATION_JOB_ID}" -n -P --format=JobIDRaw,State,ExitCode | \
  awk -F'|' -v id="${PRIOR_ALLOCATION_JOB_ID}" '$1==id && $2=="COMPLETED" && $3=="0:0" {ok=1} END {exit(ok ? 0 : 1)}'
test "$(sha256sum "${V2R1_ROOT}/logs/allocation-probe-${PRIOR_ALLOCATION_JOB_ID}.out" | awk '{print $1}')" = "${PRIOR_ALLOCATION_STDOUT_SHA}"
test "$(sha256sum "${V2R1_ROOT}/logs/allocation-probe-${PRIOR_ALLOCATION_JOB_ID}.err" | awk '{print $1}')" = "${V2R1_JOB_STDERR_SHA}"

if squeue -h -o '%j' | grep -Eq '^tukf09-455-v2r2-(map|prepare|neural)$'; then
  echo "REFUSING_EXISTING_V2R2_JOB" >&2
  exit 70
fi

# Bind the small mailbox payload before creating the new remote root.
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
test -x "${PYTHON}"
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE

"${PYTHON}" -B - "${PAYLOAD}/bundle_manifest.sha256.json" "${ARCHIVE_SHA}" "${ARCHIVE_SIZE}" "${BUILDER_SHA}" <<'PY'
import json
from pathlib import Path
import sys

outer = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
archive_sha = sys.argv[2]
archive_size = int(sys.argv[3])
builder_sha = sys.argv[4]
expected_members = {
    "kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r2.py": builder_sha,
    "kalmannet/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r2.json": "f807ebda064b9ffa17b8d601ea9dcad9bacac8744e879256bf1b2b69fbbad565",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r2/allocation_probe.slurm": "ba0181c40fe51ba401cf779e52c56394ef56a3758cd4c0dd2fdd228bf447f812",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r2/download_runtime_inputs_login.sh": "24731c5d58bd9a3b90d8932e5495db3f56ea5c0d10c5e15425c221ff7a60f6ab",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r2/probe_gpu.slurm": "ec79ac4edffc96db25cb212ae8d3786bbc6e54fda6d52814f8e57b170c6849dd",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r2/psutil-source.lock": "c021239b1cdeafff41591adec793c79820ad66ec5418dba2570ea8ff2ae60d68",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r2/runtime-binary.lock": "8bfc922ce4165eb7793f0b4f1afe9a185644858875af6a3bfd21992a23046d9f",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r2/stage_and_train.py": "dba1b40345d34119add73c976d5f878f0fc35e210d9894d7dc22da07e2c1ab81",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r2/submit_training_gpu.slurm": "6cc95e787ae15d4f6ffd1ced1ce0554661c7ca35f29d53f36f7ddb24c9504f84",
    "kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r2/verify_result.py": "6b0e97911c44e931ee131038aae2b5847507f8fe8c7cde617691a1207aef8a84",
}
assert outer["schema_version"] == "tukf09_455_a800_exclusive_training_hpc_archive_manifest_v2r2"
assert outer["archive_name"] == "tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r2_formal_training.tar.gz"
assert outer["experiment_id"] == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1"
assert outer["purpose"] == "formal_training_only_no_formal_evaluation"
assert outer["archive_sha256"] == archive_sha
assert outer["archive_size"] == archive_size
assert outer["member_count"] == 2808
assert outer["admitted_executable_count"] == 30
assert outer["admitted_test_count"] == 12
assert outer["artifact_file_count"] == 2751
assert outer["config_file_count"] == 6
assert outer["non_admitted_wrapper_count"] == 9
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

# The new technical revision must start at an absent, unique root.
if [[ -e "${ROOT}" || -L "${ROOT}" ]]; then
  echo "REFUSING_EXISTING_REMOTE_ROOT=${ROOT}" >&2
  exit 71
fi
mkdir "${ROOT}"
mkdir "${ROOT}/incoming" "${ROOT}/logs" "${ROOT}/status"
cp --no-clobber --reflink=never --dereference "${PAYLOAD}/${ARCHIVE_NAME}" "${ROOT}/incoming/${ARCHIVE_NAME}"
cp --no-clobber --reflink=never --dereference "${PAYLOAD}/bundle_manifest.sha256.json" "${ROOT}/incoming/bundle_manifest.sha256.json"
cp --no-clobber --reflink=never --dereference "${PAYLOAD}/${BUILDER_NAME}" "${ROOT}/incoming/${BUILDER_NAME}"
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
assert outer["member_count"] == 2808
assert extracted["status"] == "TUKF09_455_A800_EXCLUSIVE_V2R2_HPC_BUNDLE_VERIFIED"
assert extracted["member_count"] == 2808
assert extracted["reused"] is False
assert strict["status"] == "TUKF09_455_A800_EXCLUSIVE_V2R2_HPC_BUNDLE_VERIFIED"
assert strict["member_count"] == 2808
assert strict["admitted_executable_count"] == 30
assert strict["admitted_test_count"] == 12
assert strict["artifact_file_count"] == 2751
assert strict["formal_evaluation_output_count"] == 0
builder = root / "bundle/kalmannet/scripts/build_tukf09_455_a800_exclusive_hpc_bundle_v2r2.py"
manifest = root / "bundle/bundle_manifest.json"
login_script = root / "bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r2/download_runtime_inputs_login.sh"
assert builder.is_file() and not builder.is_symlink()
assert hashlib.sha256(builder.read_bytes()).hexdigest() == builder_sha
assert manifest.is_file() and not manifest.is_symlink()
assert hashlib.sha256(manifest.read_bytes()).hexdigest() == internal_manifest_sha
assert login_script.is_file() and not login_script.is_symlink()
assert login_script.stat().st_mode & 0o111
for forbidden in (
    root / "offline_inputs_v2r2",
    root / "runtime_v2r2",
    root / "status/allocation_probe.json",
    root / "status/preparation_probe.json",
    root / "status/hpc_technical_admission.json",
    root / "bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1",
):
    assert not forbidden.exists() and not forbidden.is_symlink(), forbidden
summary = {
    "archive_sha256": archive_sha,
    "bundle_manifest_sha256": internal_manifest_sha,
    "failed_predecessor_job_id": 217163,
    "failed_predecessor_root": "/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901",
    "formal_evaluation_authorized": False,
    "member_count": strict["member_count"],
    "offline_runtime_input_file_count": 0,
    "remote_root": str(root),
    "slurm_job_submitted": False,
    "status": "A800_EXCLUSIVE_V2R2_DEPLOYED_STRICT_BUNDLE_VERIFIED_FORMAL_EVALUATION_HOLD",
}
summary_path = root / "status/deployment_summary.json"
with summary_path.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(summary, handle, ensure_ascii=True, indent=2, sort_keys=True)
    handle.write("\n")
print(json.dumps(summary, sort_keys=True))
PY

echo "TUKF09_455_A800_EXCLUSIVE_V2R2_DEPLOYMENT_COMPLETED"
