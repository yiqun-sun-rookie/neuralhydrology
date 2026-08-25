#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/official-core-a35-one-step-v27"
EXPERIMENT_ID="DAILY_CAMELS_KNET_OFFICIAL_CORE_FIXED_FULL_TRAINING_COVERAGE_ONE_STEP_V1_20260825_A35"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_OFFICIAL_CORE_A35_ONE_STEP_SEQ27"
ARCHIVE="${PAYLOAD_DIRECTORY}/${EXPERIMENT_ID}.tar.gz"
OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/bundle_manifest.sha256.json"
ARCHIVE_SHA256="34c2c97046ba699c79512941ad5dc218f972376935aa87a0cd1484560c7ee8ef"
ARCHIVE_SIZE="260872"
OUTER_MANIFEST_SHA256="1c5733ccd7cf2db17ae7faaa95804b32b6c7f2ec2a6f11dbd0701d0b52d656a2"
OUTER_MANIFEST_SIZE="10598"
INTERNAL_MANIFEST_SHA256="81fd4819a3d88371dfdfceb6ca69035d2079516ce447b8b8e2b84ce680783126"
ACTIVE_CONFIG_SHA256="05a7021c9eed0baa19f4256c898daa36edb4b3ead37a0fd9c64b123a35d7edaf"
EXACT_RECEIPT_SHA256="70e73c9f014dc4a4d615e07087fb99a994ba30b8c867eb5ef49141a59a39b687"
CAUSAL_RECEIPT_SHA256="0f6080a05a27244eca59c58043f265718102a4c2985684fb674781c8157d6c66"

PARITY_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824"
EXACT_REPLAY_GATE="${PARITY_ROOT}/status/replay_gate_DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_EXACT_REPLAY_DTYPE_REPAIR_V3_20260825_A05.json"
CAUSAL_REPLAY_GATE="${PARITY_ROOT}/status/replay_gate_DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_CAUSAL_REPLAY_DTYPE_REPAIR_V3_20260825_A06.json"
REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_official_core_a35_20260825"
SOURCE_DIRECTORY="${REMOTE_ROOT}/source_seq27"
RUN_DIRECTORY="${REMOTE_ROOT}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${REMOTE_ROOT}/status"
LOG_DIRECTORY="${REMOTE_ROOT}/logs"
STAGING_DIRECTORY="/data1/home/sunyiq/kalmannet_daily_camels_official_core_a35_seq27_staging_20260825"
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/DAILY_CAMELS_KNET_OFFICIAL_CORE_A35_ONE_STEP_SEQ27_evidence.tar.gz"

NAMESPACE_OWNED=0
SAFE_TO_PACKAGE=0
FINAL_STATUS="SEQ27_A35_STARTED"
TRAINING_JOB_ID="NOT_SUBMITTED"

sha256_file() { sha256sum "$1" | awk '{print $1}'; }

package_evidence() {
  local command_exit_code="$1" temporary_archive
  if [[ "$NAMESPACE_OWNED" -ne 1 ]]; then
    printf 'evidence_archive=NOT_CREATED namespace_not_owned=1 status=%s exit_code=%s\n' \
      "$FINAL_STATUS" "$command_exit_code"
    return 0
  fi
  if [[ "$SAFE_TO_PACKAGE" -ne 1 ]]; then
    printf 'evidence_archive=NOT_CREATED active_job_not_terminal=1 status=%s exit_code=%s training_job_id=%s\n' \
      "$FINAL_STATUS" "$command_exit_code" "$TRAINING_JOB_ID"
    return 0
  fi
  printf '%s\n' "$FINAL_STATUS" > "${STATUS_DIRECTORY}/seq27_final_status.txt" || return 91
  printf '%s\n' "$command_exit_code" > "${STATUS_DIRECTORY}/seq27_command_exit_code.txt" || return 92
  printf '%s\n' "$TRAINING_JOB_ID" > "${STATUS_DIRECTORY}/seq27_training_job_id.txt" || return 93
  date -u +%Y-%m-%dT%H:%M:%SZ > "${STATUS_DIRECTORY}/seq27_finished_time_utc.txt" || return 94
  if [[ "$TRAINING_JOB_ID" =~ ^[0-9]+$ && ! -e "${STATUS_DIRECTORY}/seq27_sacct_resources.txt" ]]; then
    sacct -j "$TRAINING_JOB_ID" --units=K --parsable2 \
      --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,ReqMem,AllocTRES,MaxRSS,MaxVMSize,AveRSS \
      > "${STATUS_DIRECTORY}/seq27_sacct_resources.txt" 2>&1 || true
  fi
  if find "$REMOTE_ROOT" -type l -print -quit | grep -q .; then
    echo "A35 evidence root contains a symbolic link" >&2
    return 95
  fi
  mkdir -p "$OUTBOX_DIRECTORY" || return 96
  temporary_archive="$(mktemp "${STAGING_DIRECTORY}/evidence.XXXXXX.tar.gz")" || return 97
  tar -czf "$temporary_archive" -C "$(dirname "$REMOTE_ROOT")" "$(basename "$REMOTE_ROOT")" || return 98
  [[ -s "$temporary_archive" ]] && gzip -t "$temporary_archive" || return 99
  [[ ! -e "$EVIDENCE_ARCHIVE" && ! -L "$EVIDENCE_ARCHIVE" ]] || return 100
  ln -- "$temporary_archive" "$EVIDENCE_ARCHIVE" || return 101
  printf 'evidence_archive=%s\n' "$EVIDENCE_ARCHIVE"
  printf 'evidence_archive_sha256=%s\n' "$(sha256_file "$EVIDENCE_ARCHIVE")"
  printf 'evidence_archive_size=%s\n' "$(stat -c '%s' "$EVIDENCE_ARCHIVE")"
  printf 'evidence_status=%s command_exit_code=%s training_job_id=%s\n' \
    "$FINAL_STATUS" "$command_exit_code" "$TRAINING_JOB_ID"
  rm -- "$temporary_archive" || return 102
}

on_exit() {
  local main_exit_code="$?" package_exit_code=0
  trap - EXIT INT TERM
  set +e
  package_evidence "$main_exit_code"
  package_exit_code="$?"
  if [[ "$main_exit_code" -eq 0 && "$package_exit_code" -ne 0 ]]; then exit 90; fi
  exit "$main_exit_code"
}

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  echo "fixed-user check failed" >&2
  exit 50
fi
for payload in "$ARCHIVE" "$OUTER_MANIFEST" "$EXACT_REPLAY_GATE" "$CAUSAL_REPLAY_GATE"; do
  [[ -f "$payload" && ! -L "$payload" ]] || {
    echo "required A35 payload or replay receipt is absent or symbolic: $payload" >&2
    exit 51
  }
done
[[ "$(stat -c '%s' "$ARCHIVE")" = "$ARCHIVE_SIZE" ]] || { echo "A35 archive size differs" >&2; exit 52; }
[[ "$(sha256_file "$ARCHIVE")" = "$ARCHIVE_SHA256" ]] || { echo "A35 archive hash differs" >&2; exit 53; }
[[ "$(stat -c '%s' "$OUTER_MANIFEST")" = "$OUTER_MANIFEST_SIZE" ]] || { echo "A35 outer manifest size differs" >&2; exit 54; }
[[ "$(sha256_file "$OUTER_MANIFEST")" = "$OUTER_MANIFEST_SHA256" ]] || { echo "A35 outer manifest hash differs" >&2; exit 55; }
[[ "$(sha256_file "$EXACT_REPLAY_GATE")" = "$EXACT_RECEIPT_SHA256" ]] || { echo "A35 exact replay receipt differs" >&2; exit 56; }
[[ "$(sha256_file "$CAUSAL_REPLAY_GATE")" = "$CAUSAL_RECEIPT_SHA256" ]] || { echo "A35 causal replay receipt differs" >&2; exit 57; }

python - "$OUTER_MANIFEST" "$EXPERIMENT_ID" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" \
  "$INTERNAL_MANIFEST_SHA256" "$ACTIVE_CONFIG_SHA256" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if (
    manifest.get("schema_version") != "daily_camels_ukf_knet_parity_hpc_archive_v1"
    or manifest.get("experiment_id") != sys.argv[2]
    or manifest.get("archive_sha256") != sys.argv[3]
    or int(manifest.get("archive_size", -1)) != int(sys.argv[4])
    or manifest.get("internal_manifest_sha256") != sys.argv[5]
    or manifest.get("member_sha256", {}).get(
        "configs/daily_camels_knet_official_core_fixed_full_training_coverage_one_step_a35.json"
    ) != sys.argv[6]
    or int(manifest.get("member_count", -1)) != 50
    or int(manifest.get("input_archive_count", -1)) != 1
    or int(manifest.get("reserved_data_member_count", -1)) != 0
    or int(manifest.get("array_members_materialized_during_build", -1)) != 0
    or manifest.get("initialization_mode") != "causal_shared_spinup"
):
    raise SystemExit("A35 outer manifest identity or isolation policy differs")
PY

python - "$ARCHIVE" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as archive:
    members = archive.getmembers()
    if len(members) != 51:
        raise SystemExit("A35 archive member count differs")
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or not path.parts or ".." in path.parts:
            raise SystemExit(f"unsafe A35 archive member: {member.name}")
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f"unsupported A35 archive member type: {member.name}")
PY

python - "$REMOTE_ROOT" "$SOURCE_DIRECTORY" "$RUN_DIRECTORY" \
  "$STATUS_DIRECTORY" "$LOG_DIRECTORY" <<'PY'
from pathlib import Path
import sys

root, source, run, status, logs = [Path(value) for value in sys.argv[1:]]
if source == root or source.parent != root:
    raise SystemExit("A35 source directory is not an isolated direct child of the remote root")
for generated in (run, status, logs):
    if generated == source or source in generated.parents:
        raise SystemExit("A35 generated evidence would contaminate the strict bundle root")
PY

for path in "$REMOTE_ROOT" "$STAGING_DIRECTORY" "$EVIDENCE_ARCHIVE"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "isolated A35 path already exists: $path" >&2
    exit 58
  }
done

mkdir "$REMOTE_ROOT" "$STAGING_DIRECTORY"
mkdir "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY" "$LOG_DIRECTORY"
NAMESPACE_OWNED=1
SAFE_TO_PACKAGE=1
trap on_exit EXIT
trap 'FINAL_STATUS="SEQ27_A35_INTERRUPTED"; exit 143' INT TERM
date -u +%Y-%m-%dT%H:%M:%SZ > "${STATUS_DIRECTORY}/seq27_started_time_utc.txt"
{
  printf 'execution_attempt_id=%s\n' "$EXECUTION_ATTEMPT_ID"
  printf 'archive=%s\n' "$ARCHIVE"
  printf 'archive_sha256=%s\n' "$ARCHIVE_SHA256"
  printf 'archive_size_bytes=%s\n' "$ARCHIVE_SIZE"
  printf 'outer_manifest=%s\n' "$OUTER_MANIFEST"
  printf 'outer_manifest_sha256=%s\n' "$OUTER_MANIFEST_SHA256"
  printf 'exact_replay_gate=%s\n' "$EXACT_REPLAY_GATE"
  printf 'exact_replay_gate_sha256=%s\n' "$EXACT_RECEIPT_SHA256"
  printf 'causal_replay_gate=%s\n' "$CAUSAL_REPLAY_GATE"
  printf 'causal_replay_gate_sha256=%s\n' "$CAUSAL_RECEIPT_SHA256"
} > "${STATUS_DIRECTORY}/seq27_payload_identity.txt"

tar -xzf "$ARCHIVE" -C "$SOURCE_DIRECTORY"
set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${SOURCE_DIRECTORY}/src:${SOURCE_DIRECTORY}"
cd "$SOURCE_DIRECTORY"
python -u hpc/daily_camels_ukf_knet_official_core/preflight.py \
  --bundle-root "$SOURCE_DIRECTORY" \
  --phase train \
  --offline-bundle-check \
  --report "${STATUS_DIRECTORY}/seq27_offline_bundle_preflight.json"
FINAL_STATUS="SEQ27_A35_OFFLINE_BUNDLE_VERIFIED"

SAFE_TO_PACKAGE=0
if ! RAW_JOB_ID="$(sbatch --parsable --mem=0 \
  --export=ALL,PARITY_EXACT_REPLAY_GATE="${EXACT_REPLAY_GATE}",PARITY_CAUSAL_REPLAY_GATE="${CAUSAL_REPLAY_GATE}" \
  hpc/daily_camels_ukf_knet_official_core/submit_one_step_gpu.slurm)"; then
  SAFE_TO_PACKAGE=1
  FINAL_STATUS="SEQ27_A35_SUBMISSION_REJECTED_HARD_STOP"
  exit 59
fi
TRAINING_JOB_ID="${RAW_JOB_ID%%;*}"
[[ "$TRAINING_JOB_ID" =~ ^[0-9]+$ ]] || {
  SAFE_TO_PACKAGE=1
  FINAL_STATUS="SEQ27_A35_SUBMISSION_IDENTITY_HARD_STOP"
  exit 60
}
printf '%s\n' "$TRAINING_JOB_ID" > "${STATUS_DIRECTORY}/seq27_training_job_id.txt"
FINAL_STATUS="SEQ27_A35_SUBMITTED"

TERMINAL_STATE=""
TERMINAL_EXIT_CODE=""
for attempt in $(seq 1 2160); do
  ACCOUNTING_RECORD="$(sacct -n -X -j "$TRAINING_JOB_ID" --format=State,ExitCode -P 2>/dev/null | awk -F'|' 'NF {print $1 "|" $2; exit}' || true)"
  TERMINAL_STATE="${ACCOUNTING_RECORD%%|*}"
  TERMINAL_EXIT_CODE="${ACCOUNTING_RECORD#*|}"
  TERMINAL_STATE="${TERMINAL_STATE%%+*}"
  TERMINAL_STATE="${TERMINAL_STATE%% *}"
  LIVE_STATE="$(squeue -h -j "$TRAINING_JOB_ID" -o '%T' 2>/dev/null | head -1 | tr -d '[:space:]' || true)"
  case "$TERMINAL_STATE" in
    COMPLETED|FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED|SPECIAL_EXIT)
      [[ -z "$LIVE_STATE" ]] && break
      ;;
  esac
  sleep 10
done
case "$TERMINAL_STATE" in
  COMPLETED|FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED|SPECIAL_EXIT)
    SAFE_TO_PACKAGE=1
    ;;
  *)
    FINAL_STATUS="SEQ27_A35_MONITOR_TIMEOUT_JOB_LEFT_RUNNING_NO_EVIDENCE"
    exit 61
    ;;
esac
printf '%s\n' "$TERMINAL_STATE" > "${STATUS_DIRECTORY}/seq27_training_terminal_state.txt"
printf '%s\n' "$TERMINAL_EXIT_CODE" > "${STATUS_DIRECTORY}/seq27_training_terminal_exit_code.txt"
SACCT_REPORT="${STATUS_DIRECTORY}/seq27_sacct_resources.txt"
for attempt in $(seq 1 12); do
  sacct -j "$TRAINING_JOB_ID" --units=K --parsable2 \
    --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,ReqMem,AllocTRES,MaxRSS,MaxVMSize,AveRSS \
    > "$SACCT_REPORT" 2>&1 || true
  if awk -F'|' -v id="$TRAINING_JOB_ID" \
    '$1 ~ ("^" id "\\.(batch|[0-9]+)$") && $10 != "" {found=1} END {exit !found}' \
    "$SACCT_REPORT"; then
    break
  fi
  sleep 5
done

JOB_STATUS="${STATUS_DIRECTORY}/job-status-${EXPERIMENT_ID}-${TRAINING_JOB_ID}.json"
PREFLIGHT_REPORT="${STATUS_DIRECTORY}/preflight-${EXPERIMENT_ID}-${TRAINING_JOB_ID}.json"
RUNTIME_PROBE_REPORT="${STATUS_DIRECTORY}/runtime-probe-${EXPERIMENT_ID}-${TRAINING_JOB_ID}.json"
VERIFICATION_REPORT="${STATUS_DIRECTORY}/independent-verification-${EXPERIMENT_ID}-${TRAINING_JOB_ID}.json"
GPU_RESOURCE_LOG="${STATUS_DIRECTORY}/gpu-resources-${EXPERIMENT_ID}-${TRAINING_JOB_ID}.csv"
CGROUP_RESOURCE_LOG="${STATUS_DIRECTORY}/cgroup-resources-${EXPERIMENT_ID}-${TRAINING_JOB_ID}.txt"
for path in "$JOB_STATUS" "$PREFLIGHT_REPORT" "$RUNTIME_PROBE_REPORT" "$GPU_RESOURCE_LOG" "$CGROUP_RESOURCE_LOG"; do
  [[ -f "$path" && ! -L "$path" ]] || {
    FINAL_STATUS="SEQ27_A35_TERMINAL_EVIDENCE_MISSING_HARD_STOP"
    exit 62
  }
done

if [[ "$TERMINAL_STATE" = "COMPLETED" && "$TERMINAL_EXIT_CODE" = "0:0" ]]; then
  RESULT_CLASS="scientific_pass"
elif [[ "$TERMINAL_STATE" = "FAILED" && "$TERMINAL_EXIT_CODE" = "2:0" ]]; then
  RESULT_CLASS="verified_scientific_fail"
else
  FINAL_STATUS="SEQ27_A35_TRAINING_${TERMINAL_STATE:-UNKNOWN}_${TERMINAL_EXIT_CODE:-UNKNOWN}_HARD_STOP"
  exit 63
fi
[[ -f "$VERIFICATION_REPORT" && ! -L "$VERIFICATION_REPORT" ]] || {
  FINAL_STATUS="SEQ27_A35_INDEPENDENT_VERIFICATION_MISSING_HARD_STOP"
  exit 64
}
for path in "${RUN_DIRECTORY}/result_summary.json" "${RUN_DIRECTORY}/manifest.sha256.json" \
  "${RUN_DIRECTORY}/completion.marker.json" "${RUN_DIRECTORY}/epoch_history.json"; do
  [[ -f "$path" && ! -L "$path" ]] || {
    FINAL_STATUS="SEQ27_A35_RUN_EVIDENCE_MISSING_HARD_STOP"
    exit 65
  }
done

python - "$RESULT_CLASS" "$EXPERIMENT_ID" "$TRAINING_JOB_ID" "$JOB_STATUS" \
  "$PREFLIGHT_REPORT" "$RUNTIME_PROBE_REPORT" "$VERIFICATION_REPORT" \
  "${RUN_DIRECTORY}/result_summary.json" "$SACCT_REPORT" \
  "${STATUS_DIRECTORY}/seq27_result_audit.json" <<'PY'
import csv
import json
import os
from pathlib import Path
import re
import sys

result_class, experiment_id, job_id = sys.argv[1:4]
job_status, preflight, runtime, verification, summary = [
    json.loads(Path(path).read_text(encoding="utf-8")) for path in sys.argv[4:9]
]
sacct_path = Path(sys.argv[9])
audit_path = Path(sys.argv[10])
documents = (job_status, verification, summary)
if any(document.get("experiment_id") != experiment_id for document in documents):
    raise SystemExit("A35 terminal evidence experiment identity differs")
if str(job_status.get("slurm_job_id")) != job_id:
    raise SystemExit("A35 job-status Slurm identity differs")
if preflight.get("status") != "PREFLIGHT_PASS" or preflight.get("phase") != "train":
    raise SystemExit("A35 online resource preflight did not pass")
if (
    runtime.get("status") != "A35_OFFICIAL_RUNTIME_PROBE_PASS"
    or runtime.get("backend") != "pinned_upstream_kalmannet_tsp_828a2cf"
    or runtime.get("upstream_commit") != "828a2cf529bc84f43b37d543d916fe5858054457"
    or runtime.get("scalar_normalization_probe") != [1.0, -1.0, 0.0]
    or int(runtime.get("reserved_data_member_count", -1)) != 0
    or int(runtime.get("arrays_materialized", -1)) != 0
):
    raise SystemExit("A35 official runtime identity probe differs")
training = summary.get("training", {})
if (
    int(verification.get("optimizer_steps", -1)) != 1
    or int(verification.get("sampled_forecast_events", -1)) != 7650
    or int(verification.get("epoch_count_including_zero", -1)) != 2
    or int(verification.get("reserved_evaluation_access_count", -1)) != 0
    or int(verification.get("input_archive_count", -1)) != 1
    or int(verification.get("reserved_data_member_count", -1)) != 0
    or training.get("optimizer_steps") != 1
    or training.get("sampled_forecast_events") != 7650
):
    raise SystemExit("A35 independently verified training accounting differs")
metrics = verification.get("recomputed_712_origin_metrics", {})
for label in ("epoch_zero", "epoch_one", "zero_gain", "ukf"):
    if set(metrics.get(label, {})) != {"1", "2", "3"}:
        raise SystemExit(f"A35 independent metric inventory differs: {label}")
    if any(int(row.get("target_count", -1)) != 712 for row in metrics[label].values()):
        raise SystemExit(f"A35 independent target count differs: {label}")
if result_class == "scientific_pass":
    expected = (
        "complete",
        "A35_INDEPENDENT_VERIFICATION_PASS",
        True,
        "TRAINING_COMPLETE_GATE_PASS",
    )
else:
    expected = (
        "verified_scientific_fail",
        "A35_INDEPENDENT_VERIFICATION_SCIENTIFIC_FAIL",
        False,
        "TRAINING_COMPLETE_GATE_FAIL",
    )
if (
    job_status.get("stop_classification") != expected[0]
    or verification.get("status") != expected[1]
    or verification.get("scientific_passed") is not expected[2]
    or summary.get("status") != expected[3]
    or training.get("gate_passed") is not expected[2]
    or verification.get("failed_gates") != training.get("failed_gates")
):
    raise SystemExit("A35 scheduler, verifier, and scientific classifications differ")

with sacct_path.open("r", encoding="utf-8", newline="") as handle:
    rows = list(csv.DictReader(handle, delimiter="|"))
step_pattern = re.compile(rf"{re.escape(job_id)}\.(?:batch|[0-9]+)")
step_peaks = []
for row in rows:
    step_id = row.get("JobIDRaw") or ""
    if step_pattern.fullmatch(step_id) is None:
        continue
    match = re.fullmatch(
        r"([0-9]+(?:\.[0-9]+)?)([KMGT]?)", (row.get("MaxRSS") or "").strip()
    )
    if match is None:
        continue
    factor = {
        "": 1.0,
        "K": 1.0,
        "M": 1024.0,
        "G": 1024.0**2,
        "T": 1024.0**3,
    }[match.group(2)]
    step_peaks.append((int(float(match.group(1)) * factor), step_id))
if not step_peaks or max(step_peaks)[0] <= 0:
    raise SystemExit("A35 Slurm task-step MaxRSS is absent or nonpositive")
slurm_task_max_rss_kib, slurm_task_max_rss_job_step = max(step_peaks)
audit = {
    "schema_version": "daily_camels_a35_seq27_result_audit_v1",
    "status": "SEQ27_A35_TERMINAL_EVIDENCE_VERIFIED",
    "execution_attempt_id": "DAILY_CAMELS_KNET_OFFICIAL_CORE_A35_ONE_STEP_SEQ27",
    "experiment_id": experiment_id,
    "slurm_job_id": job_id,
    "result_class": result_class,
    "scientific_passed": verification["scientific_passed"],
    "failed_gates": verification["failed_gates"],
    "selected_epoch": verification["selected_epoch"],
    "checkpoint_objective_728": verification["checkpoint_objective_728"],
    "recomputed_712_origin_metrics": metrics,
    "same_batch_improvement": verification["same_batch_improvement"],
    "same_batch_strictly_improved": verification["same_batch_strictly_improved"],
    "resource_evidence": verification["resource_evidence"],
    "slurm_task_max_rss_kib": slurm_task_max_rss_kib,
    "slurm_task_max_rss_job_step": slurm_task_max_rss_job_step,
}
data = (json.dumps(audit, sort_keys=True, separators=(",", ":")) + "\n").encode()
descriptor = os.open(audit_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    os.write(descriptor, data)
finally:
    os.close(descriptor)
print(json.dumps(audit, sort_keys=True))
PY

if [[ "$RESULT_CLASS" = "scientific_pass" ]]; then
  FINAL_STATUS="SEQ27_A35_VERIFIED_SCIENTIFIC_PASS"
  echo "DAILY_CAMELS_A35_OFFICIAL_CORE_VERIFIED_SCIENTIFIC_PASS job=${TRAINING_JOB_ID}"
else
  FINAL_STATUS="SEQ27_A35_VERIFIED_SCIENTIFIC_FAIL"
  echo "DAILY_CAMELS_A35_OFFICIAL_CORE_VERIFIED_SCIENTIFIC_FAIL job=${TRAINING_JOB_ID}"
fi
