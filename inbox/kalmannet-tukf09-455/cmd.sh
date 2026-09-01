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
ADMISSION="${ROOT}/status/hpc_technical_admission.json"
ADMISSION_SHA=b485c75a86e3f39b616b9dc0292696ba24c275038a520177759c27b1c4522930
ADMISSION_IDENTITY_SHA=d97dce65ae36af7576c13cd1f30dad90f1e2f392cbf10a8f2b5e59b5af6a17f0
TRAINING_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/submit_training_gpu.slurm"
TRAINING_SCRIPT_SHA=27283ab2b4a543ce2cce464afd0a9ad86536d0ed5948eba6ba1b313147ac8fba
STAGE_TOOL="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/stage_and_train.py"
STAGE_TOOL_SHA=b5d06b6cc320d22a3248958f1670840ff9cca1d7c82dfb058746dfd1d173ae1b
VERIFIER="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/verify_result.py"
VERIFIER_SHA=5034b598df9bf84b2ee6c57ea572cf853f11b703feccef821ed3260c867f2941
EXECUTION_CONFIG="${PROJECT_ROOT}/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r4.json"
EXECUTION_CONFIG_SHA=54bb8226621c440983d1a8f4d1291b9980488296bc9658085abef47efe56b3f6
BUNDLE_MANIFEST="${ROOT}/bundle/bundle_manifest.json"
BUNDLE_MANIFEST_SHA=97eccb8c689e1c1b22577ba8823a8fb0802a14f10db213f861c5b9e3b504bdc1
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
RESULT_55="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_55.txt"
RESULT_55_COMMIT=b34410b954094246072e0b89b57fee1490030d7b
RESULT_55_SIZE=1191
RESULT_55_SHA=455796383b0c3cd0492981ff5610d5ccd564a738f303b1c4f22cd9ae45b7edd7
INSPECTION_55_COMMIT=21616744e91d451ceba4ee8fb38cdf845bc50d4e
INSPECTION_55_COMMAND_SHA=752bda702140c87d0f700d89da893c9076f76b66c558467a2b4b7f469a1af3c9
RESULT_56="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_56.txt"
RESULT_56_COMMIT=08b42196a3ddb1fa710852192f69d40cf10d6835
RESULT_56_SIZE=2439
RESULT_56_SHA=d7ef61f383a287f516b4d0d5e60975f17553fbbb009379d08f6c14f2b6b9b3d5
INSPECTION_56_COMMIT=16248b98bebc2e83b55502006614814c4f6329fc
INSPECTION_56_COMMAND_SHA=fb91c928a30a12e5e4a09ff459ac8f282a3d686184cc708d0d5c253944719bca
RESULT_57="${MAILBOX_ROOT}/outbox/kalmannet-tukf09-455/result_57.txt"
RESULT_57_COMMIT=70fe8fcdadcc5b45d95d6575cac88d8d678bdfc2
RESULT_57_SIZE=8621
RESULT_57_SHA=0e56523d1851ec983ccad5675b01bc9737c95e0fa84060afa501aeee910eb697
ADMISSION_57_COMMIT=f319f61c06d56f1f220218ec90e51cae5ecf75af
ADMISSION_57_COMMAND_SHA=dec78df4e26e2c6dfc10824e78a15eb978c8bb690762a665c355d1aea152396c
TRAINING_JOB_NAME=tukf09-455-v2r4-neural
TRAINING_JOB_ID_FILE="${ROOT}/status/training_job_id.txt"
TRAINING_SUBMISSION_LOCK="${ROOT}/status/training_submission.lock"
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

echo "=== FROZEN SEQUENCE 56 STRICT PREPARATION EVIDENCE ==="
[[ -f "${RESULT_56}" && ! -L "${RESULT_56}" ]] || fail "sequence 56 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_56}")" -eq 1 ]] || fail "sequence 56 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_56}")" -eq "${RESULT_56_SIZE}" ]] || fail "sequence 56 result size changed"
[[ "$(sha256sum "${RESULT_56}" | awk '{print $1}')" = "${RESULT_56_SHA}" ]] || fail "sequence 56 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_56.txt)" = "${RESULT_56_COMMIT}" ]] || fail "sequence 56 result commit changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_56_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_56.txt" ]] || fail "sequence 56 result commit surface changed"
git merge-base --is-ancestor "${INSPECTION_56_COMMIT}" "${RESULT_56_COMMIT}" || fail "sequence 56 command is not an ancestor of its result"
[[ "$(git show "${INSPECTION_56_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${INSPECTION_56_COMMAND_SHA}" ]] || fail "sequence 56 strict preparation command hash changed"

"${PYTHON}" -B - "${RESULT_56}" "${JOB_ID}" <<'PY'
from pathlib import Path
import json
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=56"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert any(line.startswith(f"{job_id}|tukf09-455-v2r4-prepare|hgpu8|COMPLETED|0:0|") for line in lines)
assert "STDERR_SIZE=0" in lines
assert "STDOUT_LAST_LINE=TUKF09_455_HPC_PREPARATION_PROBE_COMPLETED" in lines
assert "TUKF09_455_A800_EXCLUSIVE_V2R4_PREPARATION_COMPLETED_STRICTLY_VERIFIED_ADMISSION_NOT_CREATED" in lines
summary = next(json.loads(line) for line in lines if line.startswith('{"actual_remote_filter_seal_sha256"'))
assert summary["filter_unit_count"] == 455
assert summary["staged_file_count"] == 911
assert summary["remote_filter_seal_matches_probe"] is True
assert summary["remote_filter_verification_status"] == "FILTER_REBINDING_INDEPENDENTLY_VERIFIED_EVALUATION_HOLD"
assert summary["local_filter_seal_sha256"] == "b378ffbfde4d24ded8fbb42fdf10fef59eb04100c93879a41b4d538ae36f6ba0"
assert summary["actual_remote_filter_seal_sha256"] == "6e150cd9feba58ec35562e7fc46e7052f9e433cc5a50ae185593f1960703a55f"
PY

echo "=== FROZEN SEQUENCE 57 TECHNICAL ADMISSION EVIDENCE ==="
[[ -f "${RESULT_57}" && ! -L "${RESULT_57}" ]] || fail "sequence 57 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_57}")" -eq 1 ]] || fail "sequence 57 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_57}")" -eq "${RESULT_57_SIZE}" ]] || fail "sequence 57 result size changed"
[[ "$(sha256sum "${RESULT_57}" | awk '{print $1}')" = "${RESULT_57_SHA}" ]] || fail "sequence 57 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_57.txt)" = "${RESULT_57_COMMIT}" ]] || fail "sequence 57 result commit changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_57_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_57.txt" ]] || fail "sequence 57 result commit surface changed"
git merge-base --is-ancestor "${ADMISSION_57_COMMIT}" "${RESULT_57_COMMIT}" || fail "sequence 57 command is not an ancestor of its result"
[[ "$(git log -1 --format=%H "${RESULT_57_COMMIT}^" -- inbox/kalmannet-tukf09-455/cmd.sh)" = "${ADMISSION_57_COMMIT}" ]] || fail "sequence 57 command lineage changed"
[[ "$(git show "${ADMISSION_57_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${ADMISSION_57_COMMAND_SHA}" ]] || fail "sequence 57 technical admission command hash changed"

"${PYTHON}" -B - "${RESULT_57}" <<'PY'
from pathlib import Path
import json
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=57"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=0"
assert lines[-1].startswith("### finished=")
assert "ADMISSION_SIZE=5203" in lines
assert "ADMISSION_SHA256=b485c75a86e3f39b616b9dc0292696ba24c275038a520177759c27b1c4522930" in lines
assert "TUKF09_455_A800_EXCLUSIVE_V2R4_TECHNICAL_ADMISSION_CREATED_AND_VERIFIED_TRAINING_NOT_SUBMITTED_EVALUATION_HOLD" in lines
summary = next(json.loads(line) for line in lines if line.startswith('{"admission_identity_sha256"'))
assert summary == {
    "admission_identity_sha256": "d97dce65ae36af7576c13cd1f30dad90f1e2f392cbf10a8f2b5e59b5af6a17f0",
    "admission_sha256": "b485c75a86e3f39b616b9dc0292696ba24c275038a520177759c27b1c4522930",
    "evaluation_array_reads": 0,
    "evaluation_metrics": 0,
    "evaluation_outputs": 0,
    "evaluation_predictions": 0,
    "formal_evaluation_authorized": False,
    "neural_model_unit_count": 9,
    "ordered_basin_count": 455,
    "status": "HPC_A800_EXCLUSIVE_V2R4_TECHNICAL_EXECUTION_ADMITTED_FORMAL_EVALUATION_HOLD",
}
PY

echo "=== FROZEN SEQUENCE 55 DIAGNOSTIC EVIDENCE ==="
[[ -f "${RESULT_55}" && ! -L "${RESULT_55}" ]] || fail "sequence 55 result is missing, linked, or irregular"
[[ "$(stat -c '%h' "${RESULT_55}")" -eq 1 ]] || fail "sequence 55 result hard-link count changed"
[[ "$(stat -c '%s' "${RESULT_55}")" -eq "${RESULT_55_SIZE}" ]] || fail "sequence 55 result size changed"
[[ "$(sha256sum "${RESULT_55}" | awk '{print $1}')" = "${RESULT_55_SHA}" ]] || fail "sequence 55 result hash changed"
[[ "$(git log -1 --format=%H -- outbox/kalmannet-tukf09-455/result_55.txt)" = "${RESULT_55_COMMIT}" ]] || fail "sequence 55 result commit changed"
[[ "$(git diff-tree --no-commit-id --name-only -r "${RESULT_55_COMMIT}")" = "outbox/kalmannet-tukf09-455/result_55.txt" ]] || fail "sequence 55 result commit surface changed"
git merge-base --is-ancestor "${INSPECTION_55_COMMIT}" "${RESULT_55_COMMIT}" || fail "sequence 55 command is not an ancestor of its result"
[[ "$(git show "${INSPECTION_55_COMMIT}:inbox/kalmannet-tukf09-455/cmd.sh" | sha256sum | awk '{print $1}')" = "${INSPECTION_55_COMMAND_SHA}" ]] || fail "sequence 55 diagnostic command hash changed"

"${PYTHON}" -B - "${RESULT_55}" "${JOB_ID}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
job_id = sys.argv[2]
assert lines[0] == "### channel=kalmannet-tukf09-455 seq=55"
assert lines[1] == "### host=login4"
assert lines[-2] == "### exit_code=1"
assert lines[-1].startswith("### finished=")
assert any(line.startswith(f"{job_id}|tukf09-455-v2r4-prepare|hgpu8|COMPLETED|0:0|") for line in lines)
assert "STDERR_SIZE=0" in lines
assert "STDOUT_LAST_LINE=TUKF09_455_HPC_PREPARATION_PROBE_COMPLETED" in lines
assert "=== STRICT PREPARATION ARTIFACT GATES ===" in lines
assert '  File "<stdin>", line 110, in <module>' in lines
assert "AssertionError" in lines
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
[[ -f "${ADMISSION}" && ! -L "${ADMISSION}" ]] || fail "technical admission is missing, linked, or irregular"
[[ "$(stat -c '%h' "${ADMISSION}")" -eq 1 ]] || fail "technical admission hard-link count changed"
for item in "${TRAINING_SUBMISSION_LOCK}" "${TRAINING_JOB_ID_FILE}"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "training submission evidence exists prematurely: ${item}"
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
assert actual_remote_filter_seal_sha256 == probe_remote_filter_seal_sha256
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

echo "TUKF09_455_A800_EXCLUSIVE_V2R4_PREPARATION_COMPLETED_STRICTLY_VERIFIED_ADMISSION_NOT_CREATED"

echo "=== REVERIFY EXISTING EXCLUSIVE HPC TECHNICAL ADMISSION ==="
"${PYTHON}" -B "${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/stage_and_train.py" admit \
  --project-root "${PROJECT_ROOT}" \
  --probe "${PREPARATION_PROBE}" \
  --private-manifest "${PRIVATE_MANIFEST}" \
  --output "${ADMISSION}" \
  --authorize-hpc-technical-execution

[[ -f "${ADMISSION}" && ! -L "${ADMISSION}" ]] || fail "HPC technical admission was not created as a regular unlinked file"
[[ "$(stat -c '%h' "${ADMISSION}")" -eq 1 ]] || fail "HPC technical admission hard-link count changed"
[[ "$(sha256sum "${ADMISSION}" | awk '{print $1}')" = "${ADMISSION_SHA}" ]] || fail "HPC technical admission hash changed"
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
stage_path = project / "hpc/tukf09_455_basin_revision_a800_exclusive_v2r4/stage_and_train.py"
spec = importlib.util.spec_from_file_location("tukf09_stage_v2r4_admission_audit", stage_path)
assert spec is not None and spec.loader is not None
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)
config = stage.load_execution_config(project / "configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r4.json")
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
)
science = config["scientific_identity"]
assert admission["status"] == "HPC_A800_EXCLUSIVE_V2R4_TECHNICAL_EXECUTION_ADMITTED_FORMAL_EVALUATION_HOLD"
assert admission["scientific_contract_sha256"] == "7710594dcc5cce7f087cb70492a6f827c3925a98ea7fa051d26c5ef1660304e1"
assert admission["original_training_admission_file_sha256"] == "6ba3cdd742fc2bdf039c51afc75485c8292f0b999d7fe426cb2ccf69057c1b79"
assert admission["original_training_admission_record_sha256"] == "ca43f2ba9e35b47c76808da925508e75770bc00a37f2a89ba1dcf060017531b4"
assert admission["local_filter_installation_final_sha256"] == "b378ffbfde4d24ded8fbb42fdf10fef59eb04100c93879a41b4d538ae36f6ba0"
assert admission["remote_filter_installation_final_sha256"] == "6e150cd9feba58ec35562e7fc46e7052f9e433cc5a50ae185593f1960703a55f"
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
echo "TUKF09_455_A800_EXCLUSIVE_V2R4_TECHNICAL_ADMISSION_CREATED_AND_VERIFIED_TRAINING_NOT_SUBMITTED_EVALUATION_HOLD"

echo "=== FROZEN TRAINING SUBMISSION GATES ==="
for item in \
  "${TRAINING_SCRIPT}" \
  "${STAGE_TOOL}" \
  "${VERIFIER}" \
  "${EXECUTION_CONFIG}" \
  "${BUNDLE_MANIFEST}" \
  "${ADMISSION}" \
  "${PRIVATE_MANIFEST}" \
  "${PREPARATION_PROBE}" \
  "${STAGED_MANIFEST}" \
  "${INITIAL_BUNDLE}" \
  "${FILTER_SEAL}"; do
  [[ -f "${item}" && ! -L "${item}" ]] || fail "required training evidence is missing, linked, or irregular: ${item}"
  [[ "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required training evidence hard-link count changed: ${item}"
done
[[ "$(sha256sum "${TRAINING_SCRIPT}" | awk '{print $1}')" = "${TRAINING_SCRIPT_SHA}" ]] || fail "training Slurm wrapper hash changed"
[[ "$(sha256sum "${STAGE_TOOL}" | awk '{print $1}')" = "${STAGE_TOOL_SHA}" ]] || fail "training controller hash changed"
[[ "$(sha256sum "${VERIFIER}" | awk '{print $1}')" = "${VERIFIER_SHA}" ]] || fail "training result verifier hash changed"
[[ "$(sha256sum "${EXECUTION_CONFIG}" | awk '{print $1}')" = "${EXECUTION_CONFIG_SHA}" ]] || fail "HPC execution config hash changed"
[[ "$(sha256sum "${BUNDLE_MANIFEST}" | awk '{print $1}')" = "${BUNDLE_MANIFEST_SHA}" ]] || fail "bundle manifest hash changed"
[[ "$(sha256sum "${ADMISSION}" | awk '{print $1}')" = "${ADMISSION_SHA}" ]] || fail "technical admission hash changed before submission"
[[ "$(sha256sum "${PRIVATE_MANIFEST}" | awk '{print $1}')" = "431bb24aa9112158bd3b6289bccd28d212a22754b865f1d27c54c72387525188" ]] || fail "private runtime manifest hash changed"
[[ "$(sha256sum "${PREPARATION_PROBE}" | awk '{print $1}')" = "28649e6d68e8f699ba583d9feb0ea4c3a17f99981341ec1102ed5cb459b98210" ]] || fail "preparation probe hash changed"
[[ "$(sha256sum "${STAGED_MANIFEST}" | awk '{print $1}')" = "3bf1a5b5f6dca172f0bd8ad0e1228d94799d5fda1ae9216c68338a0084a3f197" ]] || fail "staged source manifest hash changed"
[[ "$(sha256sum "${INITIAL_BUNDLE}" | awk '{print $1}')" = "07bd84ca563711de09bb06897f3ceb9b8a324b9c6d090e02c664d910a95a77d5" ]] || fail "initial bundle verification hash changed"
[[ "$(sha256sum "${FILTER_SEAL}" | awk '{print $1}')" = "6e150cd9feba58ec35562e7fc46e7052f9e433cc5a50ae185593f1960703a55f" ]] || fail "remote filter seal hash changed"
[[ ! -e "${RESULTS_ROOT}/neural" && ! -L "${RESULTS_ROOT}/neural" ]] || fail "neural training output already exists"
[[ ! -e "${TRAINING_SUBMISSION_LOCK}" && ! -L "${TRAINING_SUBMISSION_LOCK}" ]] || fail "training submission lock already exists"
[[ ! -e "${TRAINING_JOB_ID_FILE}" && ! -L "${TRAINING_JOB_ID_FILE}" ]] || fail "training job id record already exists"
if compgen -G "${ROOT}/logs/training-*.out" >/dev/null || compgen -G "${ROOT}/logs/training-*.err" >/dev/null; then
  fail "training logs already exist"
fi
if compgen -G "${ROOT}/status/training_verification.*.json" >/dev/null; then
  fail "training verification already exists"
fi
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists before training submission: ${name}"
done

echo "=== SAME-NAME TRAINING JOB GATE ==="
set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot inspect current jobs: ${squeue_output}"
same_name=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${TRAINING_JOB_NAME}" '$2==name {print $0}')
[[ -z "${same_name}" ]] || fail "same-name training job already exists: ${same_name}"

echo "=== EXCLUSIVE TRAINING SUBMISSION LOCK ==="
mkdir "${TRAINING_SUBMISSION_LOCK}" || fail "cannot acquire the training submission lock"
[[ -d "${TRAINING_SUBMISSION_LOCK}" && ! -L "${TRAINING_SUBMISSION_LOCK}" ]] || fail "training submission lock is linked or irregular"
[[ ! -e "${TRAINING_JOB_ID_FILE}" && ! -L "${TRAINING_JOB_ID_FILE}" ]] || fail "training job id record appeared after lock acquisition"
set +e
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j|%T' 2>&1)
squeue_rc=$?
set -e
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot recheck current jobs after lock acquisition: ${squeue_output}"
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
echo "TUKF09_455_A800_EXCLUSIVE_V2R4_NEURAL_TRAINING_SUBMITTED_ONCE_FORMAL_EVALUATION_HOLD"
