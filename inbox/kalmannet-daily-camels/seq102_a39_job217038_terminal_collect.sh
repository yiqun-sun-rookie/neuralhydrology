#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
JOB_ID="217038"
EXPERIMENT_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_V1_20260831_A39"
EXECUTION_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL5_SEQ98"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_INBOX="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
CHANNEL_OUTBOX="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"
RESULT100="${CHANNEL_OUTBOX}/result_100.txt"
RESULT101="${CHANNEL_OUTBOX}/result_101.txt"
RUN_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation5_20260831"
STATUS_ROOT="${RUN_ROOT}/status"
SOURCE_ROOT="${RUN_ROOT}/source_A39_formal_evaluation_seq98"
EVALUATION_ROOT="${RUN_ROOT}/evaluation"
VERIFICATION_ROOT="${RUN_ROOT}/verification"
LOCK_ROOT="${STATUS_ROOT}/locks/${EXECUTION_ID}.submission.lock"
RUNTIME_LOCK="${STATUS_ROOT}/locks/${EXECUTION_ID}.evaluation.lock"
CHECKPOINT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_a800_train1_20260828/runs/DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH40_TO80_RESUME_STEP_MONOTONICITY_DIAGNOSTIC_V1_20260828_A38/checkpoints/epoch_075.pt"
CONFIG="${SOURCE_ROOT}/configs/daily_camels_knet_epoch75_formal_evaluation_a39.json"
SLURM_ENTRY="${SOURCE_ROOT}/hpc/daily_camels_knet_formal_evaluation/submit_evaluation_gpu.slurm"
GPU_LOG="${STATUS_ROOT}/gpu-resources-${EXECUTION_ID}-${JOB_ID}.csv"
CGROUP_LOG="${STATUS_ROOT}/cgroup-resources-${EXECUTION_ID}-${JOB_ID}.txt"
EVALUATION_START="${STATUS_ROOT}/evaluation-start-${EXECUTION_ID}-${JOB_ID}.epoch"
EVALUATION_END="${STATUS_ROOT}/evaluation-end-${EXECUTION_ID}-${JOB_ID}.epoch"
EVALUATION_EXIT="${STATUS_ROOT}/evaluation-exit-${EXECUTION_ID}-${JOB_ID}.txt"
VERIFICATION_EXIT="${STATUS_ROOT}/verification-exit-${EXECUTION_ID}-${JOB_ID}.txt"
PREFLIGHT="${STATUS_ROOT}/preflight-${EXECUTION_ID}-${JOB_ID}.json"
RESULT_SUMMARY="${EVALUATION_ROOT}/result_summary.json"
ACCESS_LEDGER="${EVALUATION_ROOT}/access_ledger.json"
EVALUATION_MANIFEST="${EVALUATION_ROOT}/manifest.sha256.json"
PREDICTIONS="${EVALUATION_ROOT}/predictions.npz"
INDEPENDENT_VERIFICATION="${VERIFICATION_ROOT}/independent_verification.json"
SLURM_STDOUT="${RUN_ROOT}/logs/evaluation-${JOB_ID}.out"
SLURM_STDERR="${RUN_ROOT}/logs/evaluation-${JOB_ID}.err"
FAILED_ARCHIVE101="${CHANNEL_OUTBOX}/DAILY_CAMELS_KNET_A39_JOB217038_TERMINAL_EVIDENCE_SEQ101.tar.gz"
ARCHIVE="${CHANNEL_OUTBOX}/DAILY_CAMELS_KNET_A39_JOB217038_TERMINAL_EVIDENCE_SEQ102.tar.gz"
COLLECTOR_SOURCE="${CHANNEL_INBOX}/seq102_a39_job217038_terminal_collect.sh"
CMD_SOURCE="${CHANNEL_INBOX}/cmd.sh"
DISPATCH_SNAPSHOT="${CHANNEL_INBOX}/seq102_a39_dispatch_cmd.sh"

RESULT100_SHA256="7f2f58ef81e9dd91836f1a962b3c7333a5bd3e48e0fef00596069b72b4ac179c"
RESULT100_SIZE="58391"
RESULT101_SHA256="6a588f234306681d76cd9da8195acbf19ad6de4d83974bb88ebf8dd982bfd2d5"
RESULT101_SIZE="4272"
RESULT_SUMMARY_SHA256="0c5be30d87618ffe52584b48f9ad889568babede7ad9b414235eda98d7bff994"
RESULT_SUMMARY_SIZE="8948"
ACCESS_LEDGER_SHA256="7d01a372818603a2ab38d58ae10f6eb8c53894b08bb6d84d9375564e4507c757"
ACCESS_LEDGER_SIZE="660"
INDEPENDENT_VERIFICATION_SHA256="735fb1facd3db4fbd6fdeb90a5c8a870f826ec2eb1d1927cae3a3af2f69f11bc"
INDEPENDENT_VERIFICATION_SIZE="9944"
PREDICTIONS_SHA256="5ba30d6cc64d875e5621e65b33a41eaeaaee3cf3d7b06f19012dd09d86494de3"
PREDICTIONS_SIZE="866624"
CHECKPOINT_SHA256="7cc97138669531688dcd65d606d154330f260346c7c9c6e704cb1be5307a241b"
CHECKPOINT_SIZE="4260296"
CONFIG_SHA256="573f5a7f58fec05445bd284c3ec550846b5c74900ea7459994ed778405d154ff"
CONFIG_SIZE="10354"
SLURM_ENTRY_SHA256="c499f3175da8c36f553e99c09c88e417820c0292d4be1fea1382108ab6770276"
SLURM_ENTRY_SIZE="20763"
EVALUATION_MANIFEST_SHA256="5ab6e6c5a208701870f1c8903d2aef47a2e7cde468b22f4172f9e48167e042a2"
GPU_LOG_SHA256="15707f5f947e439d1c244d641cc3d22ac2416b821835cb3fa9be97c36b82645e"
GPU_LOG_SIZE="11735"
CGROUP_LOG_SHA256="0da11f7ec0716501b00f806c180553f05d27ce9b6dc07f8df691b78a979774af"
CGROUP_LOG_SIZE="129"
PREFLIGHT_SHA256="c7b8a054bc6a87b83e3ddaae831bc86e380cb898c441e00f325466f3b84c9280"
PREFLIGHT_SIZE="7401"
EVALUATION_START_SHA256="3a85737c39354113fa7d1e62a9e1c9d18fa76a25e6cdcea2bbc95e1f0e9baa2a"
EVALUATION_START_SIZE="11"
EVALUATION_END_SHA256="6f281b7361d587a611647207ccfa9e5d6dddce00b6df7c27fbc2f461bbe8f1f8"
EVALUATION_END_SIZE="11"
ZERO_EXIT_SHA256="9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa"
ZERO_EXIT_SIZE="2"
SLURM_STDOUT_SHA256="7c731eed371430a82d22743c27df8359599875697bf34c8e5503b94fcd262212"
SLURM_STDOUT_SIZE="7381"
SLURM_STDERR_SHA256="8483a4189b2cdeaf207284bfad987504b2ca1423389eb282796374ff524212a8"
SLURM_STDERR_SIZE="147"
SUBMISSION_OWNER_SHA256="df418fd2fd2c266e7f73332ce242cab4252aa2a7db3f10d7db9c23ae3bc8c705"
SUBMISSION_OWNER_SIZE="2466"
SUBMISSION_BOUND_SHA256="21ca698195dd07cd16f2d9af37c58424cf0e343ee56332ffb81f8b8f4502c623"
SUBMISSION_BOUND_SIZE="458"

[[ "$(id -un)" == "${EXPECTED_USER}" ]] || { echo "fixed user differs" >&2; exit 40; }
[[ ! -e "${ARCHIVE}" && ! -L "${ARCHIVE}" ]] || { echo "terminal evidence archive already exists" >&2; exit 41; }
[[ ! -e "${FAILED_ARCHIVE101}" && ! -L "${FAILED_ARCHIVE101}" ]] || { echo "failed sequence 101 unexpectedly published an archive" >&2; exit 41; }
[[ ! -e "${RUNTIME_LOCK}" && ! -L "${RUNTIME_LOCK}" ]] || { echo "A39 evaluation lock remains active" >&2; exit 42; }
[[ -d "${LOCK_ROOT}" && ! -L "${LOCK_ROOT}" ]] || { echo "persistent A39 submission lock is absent or unsafe" >&2; exit 42; }

require_regular_identity() {
  local path="$1" expected_sha="$2" expected_size="$3" label="$4"
  [[ -f "${path}" && ! -L "${path}" ]] || { echo "${label} is absent or unsafe" >&2; exit 43; }
  [[ "$(stat -c '%s' "${path}")" == "${expected_size}" ]] || { echo "${label} size differs" >&2; exit 43; }
  [[ "$(sha256sum "${path}" | awk '{print $1}')" == "${expected_sha}" ]] || { echo "${label} identity differs" >&2; exit 43; }
}

require_regular_identity "${RESULT100}" "${RESULT100_SHA256}" "${RESULT100_SIZE}" "sequence 100 diagnostic receipt"
require_regular_identity "${RESULT101}" "${RESULT101_SHA256}" "${RESULT101_SIZE}" "sequence 101 failed collection receipt"
require_regular_identity "${RESULT_SUMMARY}" "${RESULT_SUMMARY_SHA256}" "${RESULT_SUMMARY_SIZE}" "A39 result summary"
require_regular_identity "${ACCESS_LEDGER}" "${ACCESS_LEDGER_SHA256}" "${ACCESS_LEDGER_SIZE}" "A39 access ledger"
require_regular_identity "${INDEPENDENT_VERIFICATION}" "${INDEPENDENT_VERIFICATION_SHA256}" "${INDEPENDENT_VERIFICATION_SIZE}" "A39 independent verification"
require_regular_identity "${PREDICTIONS}" "${PREDICTIONS_SHA256}" "${PREDICTIONS_SIZE}" "A39 prediction artifact"
require_regular_identity "${CHECKPOINT}" "${CHECKPOINT_SHA256}" "${CHECKPOINT_SIZE}" "epoch 75 checkpoint"
require_regular_identity "${CONFIG}" "${CONFIG_SHA256}" "${CONFIG_SIZE}" "A39 frozen configuration"
require_regular_identity "${SLURM_ENTRY}" "${SLURM_ENTRY_SHA256}" "${SLURM_ENTRY_SIZE}" "A39 Slurm entry"
require_regular_identity "${GPU_LOG}" "${GPU_LOG_SHA256}" "${GPU_LOG_SIZE}" "A39 GPU resource log"
require_regular_identity "${CGROUP_LOG}" "${CGROUP_LOG_SHA256}" "${CGROUP_LOG_SIZE}" "A39 cgroup resource log"
require_regular_identity "${PREFLIGHT}" "${PREFLIGHT_SHA256}" "${PREFLIGHT_SIZE}" "A39 preflight report"
[[ -f "${EVALUATION_MANIFEST}" && ! -L "${EVALUATION_MANIFEST}" ]] || { echo "A39 evaluation manifest is absent or unsafe" >&2; exit 43; }
[[ "$(sha256sum "${EVALUATION_MANIFEST}" | awk '{print $1}')" == "${EVALUATION_MANIFEST_SHA256}" ]] || { echo "A39 evaluation manifest identity differs" >&2; exit 43; }

require_regular_identity "${EVALUATION_START}" "${EVALUATION_START_SHA256}" "${EVALUATION_START_SIZE}" "A39 evaluation start marker"
require_regular_identity "${EVALUATION_END}" "${EVALUATION_END_SHA256}" "${EVALUATION_END_SIZE}" "A39 evaluation end marker"
require_regular_identity "${EVALUATION_EXIT}" "${ZERO_EXIT_SHA256}" "${ZERO_EXIT_SIZE}" "A39 evaluator exit record"
require_regular_identity "${VERIFICATION_EXIT}" "${ZERO_EXIT_SHA256}" "${ZERO_EXIT_SIZE}" "A39 verifier exit record"
require_regular_identity "${SLURM_STDOUT}" "${SLURM_STDOUT_SHA256}" "${SLURM_STDOUT_SIZE}" "A39 Slurm stdout"
require_regular_identity "${SLURM_STDERR}" "${SLURM_STDERR_SHA256}" "${SLURM_STDERR_SIZE}" "A39 Slurm stderr"
require_regular_identity "${LOCK_ROOT}/owner.json" "${SUBMISSION_OWNER_SHA256}" "${SUBMISSION_OWNER_SIZE}" "A39 submission owner"
require_regular_identity "${LOCK_ROOT}/bound.json" "${SUBMISSION_BOUND_SHA256}" "${SUBMISSION_BOUND_SIZE}" "A39 bound submission owner"
[[ -f "${COLLECTOR_SOURCE}" && ! -L "${COLLECTOR_SOURCE}" ]] || { echo "A39 collector source is absent or unsafe" >&2; exit 44; }
[[ -f "${CMD_SOURCE}" && ! -L "${CMD_SOURCE}" ]] || { echo "A39 mailbox command is absent or unsafe" >&2; exit 44; }
[[ -f "${DISPATCH_SNAPSHOT}" && ! -L "${DISPATCH_SNAPSHOT}" ]] || { echo "A39 dispatch snapshot is absent or unsafe" >&2; exit 44; }
cmp -s -- "${CMD_SOURCE}" "${DISPATCH_SNAPSHOT}" || { echo "A39 mailbox command differs from its dispatch snapshot" >&2; exit 44; }
[[ "$(tr -d '[:space:]' < "${EVALUATION_EXIT}")" == "0" ]] || { echo "formal evaluator did not exit zero" >&2; exit 45; }
[[ "$(tr -d '[:space:]' < "${VERIFICATION_EXIT}")" == "0" ]] || { echo "independent verifier did not exit zero" >&2; exit 45; }
grep -Fxq 'A39_FORMAL_EVALUATION_COMPLETE capability=PASS comparison=NO_DISCERNIBLE_ADVANTAGE scale_up=GO convergence=UNKNOWN_NOT_ESTABLISHED_BY_SINGLE_CHECKPOINT_FORMAL_EVALUATION' "${SLURM_STDOUT}" || { echo "formal completion marker differs" >&2; exit 45; }
grep -Fxq 'INDEPENDENT_VERIFICATION_PASS capability=PASS comparison=NO_DISCERNIBLE_ADVANTAGE scale_up=GO' "${SLURM_STDOUT}" || { echo "independent completion marker differs" >&2; exit 45; }
grep -Fxq 'RuntimeError: successful A39 entry lacks complete A800 resource coverage' "${SLURM_STDERR}" || { echo "recorded cleanup-only failure differs" >&2; exit 45; }
grep -Fxq '### channel=kalmannet-daily-camels seq=101' "${RESULT101}" || { echo "sequence 101 receipt header differs" >&2; exit 45; }
grep -Fxq "tar: unrecognized option '--sort=name'" "${RESULT101}" || { echo "sequence 101 packaging failure differs" >&2; exit 45; }
grep -Fxq '### exit_code=1' "${RESULT101}" || { echo "sequence 101 receipt exit differs" >&2; exit 45; }

[[ ! -e "${EVALUATION_ROOT}/failure.json" && ! -L "${EVALUATION_ROOT}/failure.json" ]] || { echo "unexpected A39 scientific failure artifact exists" >&2; exit 46; }

ARCHIVE_TEMP=""
ARCHIVE_PUBLISHED=0
STAGING_ROOT="$(mktemp -d "/data1/home/sunyiq/a39-seq102-terminal.XXXXXXXX")"
cleanup() {
  if [[ -n "${ARCHIVE_TEMP}" ]]; then
    case "${ARCHIVE_TEMP}" in
      "${CHANNEL_OUTBOX}/DAILY_CAMELS_KNET_A39_JOB217038_TERMINAL_EVIDENCE_SEQ102.tar.gz.tmp."*)
        if [[ "${ARCHIVE_PUBLISHED}" == "1" && -e "${ARCHIVE}" && "${ARCHIVE}" -ef "${ARCHIVE_TEMP}" ]]; then
          rm -f -- "${ARCHIVE}"
        fi
        rm -f -- "${ARCHIVE_TEMP}"
        ;;
      *) echo "refusing unsafe archive-temp cleanup: ${ARCHIVE_TEMP}" >&2 ;;
    esac
  fi
  case "${STAGING_ROOT}" in
    /data1/home/sunyiq/a39-seq102-terminal.*) rm -rf -- "${STAGING_ROOT}" ;;
    *) echo "refusing unsafe staging cleanup: ${STAGING_ROOT}" >&2 ;;
  esac
}
trap cleanup EXIT
EVIDENCE_ROOT="${STAGING_ROOT}/DAILY_CAMELS_KNET_A39_JOB217038_TERMINAL_EVIDENCE_SEQ102"
mkdir -p "${EVIDENCE_ROOT}/safe_reports" "${EVIDENCE_ROOT}/resource_evidence" "${EVIDENCE_ROOT}/lock_evidence"

cp -- "${RESULT_SUMMARY}" "${EVIDENCE_ROOT}/safe_reports/result_summary.json"
cp -- "${ACCESS_LEDGER}" "${EVIDENCE_ROOT}/safe_reports/access_ledger.json"
cp -- "${EVALUATION_MANIFEST}" "${EVIDENCE_ROOT}/safe_reports/evaluation_manifest.json"
cp -- "${INDEPENDENT_VERIFICATION}" "${EVIDENCE_ROOT}/safe_reports/independent_verification.json"
cp -- "${PREFLIGHT}" "${EVIDENCE_ROOT}/resource_evidence/preflight.json"
cp -- "${GPU_LOG}" "${EVIDENCE_ROOT}/resource_evidence/gpu_resources.csv"
cp -- "${CGROUP_LOG}" "${EVIDENCE_ROOT}/resource_evidence/cgroup_resources.txt"
cp -- "${EVALUATION_START}" "${EVIDENCE_ROOT}/resource_evidence/evaluation_start.epoch"
cp -- "${EVALUATION_END}" "${EVIDENCE_ROOT}/resource_evidence/evaluation_end.epoch"
cp -- "${EVALUATION_EXIT}" "${EVIDENCE_ROOT}/safe_reports/evaluation_exit.txt"
cp -- "${VERIFICATION_EXIT}" "${EVIDENCE_ROOT}/safe_reports/verification_exit.txt"
cp -- "${SLURM_STDOUT}" "${EVIDENCE_ROOT}/safe_reports/slurm_stdout.txt"
cp -- "${SLURM_STDERR}" "${EVIDENCE_ROOT}/safe_reports/slurm_stderr.txt"
cp -- "${LOCK_ROOT}/owner.json" "${EVIDENCE_ROOT}/lock_evidence/submission_owner.json"
cp -- "${LOCK_ROOT}/bound.json" "${EVIDENCE_ROOT}/lock_evidence/submission_bound.json"
cp -- "${RESULT100}" "${EVIDENCE_ROOT}/sequence_100_terminal_diagnostic.txt"
cp -- "${RESULT101}" "${EVIDENCE_ROOT}/sequence_101_failed_collection.txt"

require_regular_identity "${EVIDENCE_ROOT}/safe_reports/result_summary.json" "${RESULT_SUMMARY_SHA256}" "${RESULT_SUMMARY_SIZE}" "staged A39 result summary"
require_regular_identity "${EVIDENCE_ROOT}/safe_reports/access_ledger.json" "${ACCESS_LEDGER_SHA256}" "${ACCESS_LEDGER_SIZE}" "staged A39 access ledger"
require_regular_identity "${EVIDENCE_ROOT}/safe_reports/independent_verification.json" "${INDEPENDENT_VERIFICATION_SHA256}" "${INDEPENDENT_VERIFICATION_SIZE}" "staged A39 independent verification"
[[ "$(sha256sum "${EVIDENCE_ROOT}/safe_reports/evaluation_manifest.json" | awk '{print $1}')" == "${EVALUATION_MANIFEST_SHA256}" ]] || { echo "staged A39 evaluation manifest differs" >&2; exit 44; }
require_regular_identity "${EVIDENCE_ROOT}/resource_evidence/preflight.json" "${PREFLIGHT_SHA256}" "${PREFLIGHT_SIZE}" "staged A39 preflight"
require_regular_identity "${EVIDENCE_ROOT}/resource_evidence/gpu_resources.csv" "${GPU_LOG_SHA256}" "${GPU_LOG_SIZE}" "staged A39 GPU log"
require_regular_identity "${EVIDENCE_ROOT}/resource_evidence/cgroup_resources.txt" "${CGROUP_LOG_SHA256}" "${CGROUP_LOG_SIZE}" "staged A39 cgroup log"
require_regular_identity "${EVIDENCE_ROOT}/resource_evidence/evaluation_start.epoch" "${EVALUATION_START_SHA256}" "${EVALUATION_START_SIZE}" "staged A39 start marker"
require_regular_identity "${EVIDENCE_ROOT}/resource_evidence/evaluation_end.epoch" "${EVALUATION_END_SHA256}" "${EVALUATION_END_SIZE}" "staged A39 end marker"
require_regular_identity "${EVIDENCE_ROOT}/safe_reports/evaluation_exit.txt" "${ZERO_EXIT_SHA256}" "${ZERO_EXIT_SIZE}" "staged A39 evaluator exit"
require_regular_identity "${EVIDENCE_ROOT}/safe_reports/verification_exit.txt" "${ZERO_EXIT_SHA256}" "${ZERO_EXIT_SIZE}" "staged A39 verifier exit"
require_regular_identity "${EVIDENCE_ROOT}/safe_reports/slurm_stdout.txt" "${SLURM_STDOUT_SHA256}" "${SLURM_STDOUT_SIZE}" "staged A39 stdout"
require_regular_identity "${EVIDENCE_ROOT}/safe_reports/slurm_stderr.txt" "${SLURM_STDERR_SHA256}" "${SLURM_STDERR_SIZE}" "staged A39 stderr"
require_regular_identity "${EVIDENCE_ROOT}/lock_evidence/submission_owner.json" "${SUBMISSION_OWNER_SHA256}" "${SUBMISSION_OWNER_SIZE}" "staged A39 submission owner"
require_regular_identity "${EVIDENCE_ROOT}/lock_evidence/submission_bound.json" "${SUBMISSION_BOUND_SHA256}" "${SUBMISSION_BOUND_SIZE}" "staged A39 bound owner"
require_regular_identity "${EVIDENCE_ROOT}/sequence_100_terminal_diagnostic.txt" "${RESULT100_SHA256}" "${RESULT100_SIZE}" "staged sequence 100 receipt"
require_regular_identity "${EVIDENCE_ROOT}/sequence_101_failed_collection.txt" "${RESULT101_SHA256}" "${RESULT101_SIZE}" "staged sequence 101 failed receipt"

SACCT_FILE="${EVIDENCE_ROOT}/resource_evidence/slurm_accounting.txt"
sacct -n -j "${JOB_ID}" --units=K --parsable2 \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,ElapsedRaw,Start,End,NodeList,AllocCPUS,ReqMem,AllocTRES,ReqTRES,MaxRSS,MaxVMSize,AveRSS \
  > "${SACCT_FILE}"
[[ -s "${SACCT_FILE}" ]] || { echo "Slurm accounting is empty" >&2; exit 47; }

SQUEUE_FILE="${EVIDENCE_ROOT}/resource_evidence/slurm_user_active_queue.txt"
SQUEUE_STDERR="${EVIDENCE_ROOT}/resource_evidence/slurm_user_active_queue.stderr.txt"
squeue -h -u "${EXPECTED_USER}" -o '%i|%j|%u|%P|%T|%R' > "${SQUEUE_FILE}" 2> "${SQUEUE_STDERR}" || {
  echo "Slurm active-queue query failed" >&2
  exit 47
}
if awk -F '|' -v job="${JOB_ID}" '$1 == job {found=1} END {exit found ? 0 : 1}' "${SQUEUE_FILE}"; then
  echo "completed A39 job remains in active queue" >&2
  exit 47
fi

RESOURCE_SUMMARY="${EVIDENCE_ROOT}/resource_evidence/resource_summary.json"
SCIENTIFIC_SUMMARY="${EVIDENCE_ROOT}/safe_reports/terminal_scientific_summary.json"
python -S - \
  "${JOB_ID}" "${EXPERIMENT_ID}" "${EXECUTION_ID}" \
  "${SACCT_FILE}" "0" "${EVIDENCE_ROOT}/resource_evidence/gpu_resources.csv" "${EVIDENCE_ROOT}/resource_evidence/cgroup_resources.txt" \
  "${EVIDENCE_ROOT}/resource_evidence/evaluation_start.epoch" "${EVIDENCE_ROOT}/resource_evidence/evaluation_end.epoch" "${EVIDENCE_ROOT}/resource_evidence/preflight.json" \
  "${EVIDENCE_ROOT}/safe_reports/result_summary.json" "${EVIDENCE_ROOT}/safe_reports/access_ledger.json" "${EVIDENCE_ROOT}/safe_reports/evaluation_manifest.json" "${EVIDENCE_ROOT}/safe_reports/independent_verification.json" \
  "${RESOURCE_SUMMARY}" "${SCIENTIFIC_SUMMARY}" <<'PY'
import csv
import datetime as dt
import json
import math
import pathlib
import re
import sys

(
    job_id,
    experiment_id,
    execution_id,
    sacct_name,
    squeue_exit_text,
    gpu_name,
    cgroup_name,
    start_name,
    end_name,
    preflight_name,
    result_name,
    ledger_name,
    manifest_name,
    verification_name,
    resource_output_name,
    scientific_output_name,
) = sys.argv[1:]

def load_json(name):
    return json.loads(pathlib.Path(name).read_text(encoding="utf-8"))

def write_json(name, payload):
    path = pathlib.Path(name)
    with path.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)
        stream.write("\n")

def parse_kib(value):
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)K", value.strip())
    return int(float(match.group(1)) * 1024) if match else None

sacct_rows = []
with pathlib.Path(sacct_name).open("r", encoding="utf-8", newline="") as stream:
    for row in csv.DictReader(
        stream,
        fieldnames=[
            "job_id", "job_name", "user", "partition", "state", "exit_code",
            "elapsed", "elapsed_raw", "start", "end", "node_list", "alloc_cpus",
            "requested_memory", "allocated_resources", "requested_resources",
            "max_rss", "max_vm_size", "average_rss",
        ],
        delimiter="|",
    ):
        if row.get("job_id"):
            sacct_rows.append(row)
if not sacct_rows:
    raise SystemExit("Slurm accounting has no rows")
main_rows = [row for row in sacct_rows if row["job_id"] == job_id]
if len(main_rows) != 1:
    raise SystemExit("Slurm accounting lacks one unique main job row")
main = main_rows[0]
if not (
    main["job_name"] == "daily-knet-a39-s98"
    and main["user"] == "sunyiq"
    and main["partition"] == "hgpu8"
    and main["state"] == "FAILED"
    and main["exit_code"] == "72:0"
    and main["node_list"] == "ngu202"
):
    raise SystemExit("A39 main Slurm identity or cleanup-only terminal state differs")
expected_steps = {
    f"{job_id}.0": "preflight",
    f"{job_id}.1": "formal_evaluator",
    f"{job_id}.2": "independent_verifier",
}
step_memory = []
for expected_step_id, role in expected_steps.items():
    matching = [row for row in sacct_rows if row["job_id"] == expected_step_id]
    if len(matching) != 1:
        raise SystemExit(f"Slurm accounting lacks one unique {role} step")
    row = matching[0]
    if row["state"] != "COMPLETED" or row["exit_code"] != "0:0":
        raise SystemExit(f"A39 {role} Slurm step did not complete successfully")
    rss_bytes = parse_kib(row["max_rss"])
    vm_bytes = parse_kib(row["max_vm_size"])
    step_memory.append(
        {
            "job_id": row["job_id"],
            "role": role,
            "state": row["state"],
            "exit_code": row["exit_code"],
            "max_rss_raw": row["max_rss"],
            "max_rss_bytes": rss_bytes,
            "max_vm_size_raw": row["max_vm_size"],
            "max_vm_size_bytes": vm_bytes,
        }
    )
evaluator_step = next(row for row in step_memory if row["role"] == "formal_evaluator")
if not (
    evaluator_step["max_rss_bytes"] is not None
    and evaluator_step["max_rss_bytes"] > 0
    and evaluator_step["max_vm_size_bytes"] is not None
    and evaluator_step["max_vm_size_bytes"] > 0
):
    raise SystemExit("formal evaluator Slurm host-memory peaks are absent")

gpu_rows = []
with pathlib.Path(gpu_name).open("r", encoding="utf-8", newline="") as stream:
    for row in csv.DictReader(stream):
        sample_time = dt.datetime.strptime(row["timestamp"].strip(), "%Y/%m/%d %H:%M:%S.%f")
        gpu_rows.append(
            {
                "epoch_seconds": int(row["epoch_seconds"]),
                "timestamp": sample_time,
                "uuid": row["uuid"].strip(),
                "name": row["name"].strip(),
                "total_mib": int(row["memory_total_mib"]),
                "used_mib": int(row["memory_used_mib"]),
                "free_mib": int(row["memory_free_mib"]),
                "utilization_percent": int(row["utilization_gpu_percent"]),
            }
        )
if len(gpu_rows) != 95:
    raise SystemExit("A39 GPU sample count differs")
if any(row["name"] != "NVIDIA A800-SXM4-80GB" for row in gpu_rows):
    raise SystemExit("A39 GPU identity differs")
if len({row["uuid"] for row in gpu_rows}) != 1 or len({row["total_mib"] for row in gpu_rows}) != 1:
    raise SystemExit("A39 GPU allocation changed during evaluation")
raw_gaps = [
    (right["timestamp"] - left["timestamp"]).total_seconds()
    for left, right in zip(gpu_rows, gpu_rows[1:])
]
if not raw_gaps or min(raw_gaps) <= 0 or max(raw_gaps) > 2.0:
    raise SystemExit("A39 GPU sampling has a substantive gap")
epoch_values = [row["epoch_seconds"] for row in gpu_rows]
epoch_gaps = [right - left for left, right in zip(epoch_values, epoch_values[1:])]
if not epoch_gaps or min(epoch_gaps) <= 0 or max(epoch_gaps) > 10:
    raise SystemExit("A39 same-clock GPU epoch sampling has a substantive gap")
evaluation_start = int(pathlib.Path(start_name).read_text(encoding="ascii").strip())
evaluation_end = int(pathlib.Path(end_name).read_text(encoding="ascii").strip())
end_local = dt.datetime.fromtimestamp(evaluation_end)
raw_timestamp_last_to_end_seconds = (end_local - gpu_rows[-1]["timestamp"]).total_seconds()
epoch_last_to_end_seconds = evaluation_end - epoch_values[-1]
epoch_span_difference_seconds = abs(
    (epoch_values[-1] - epoch_values[0]) - (evaluation_end - evaluation_start)
)
if not (
    epoch_values[0] <= evaluation_start
    and 0 <= epoch_last_to_end_seconds <= max(epoch_gaps)
    and epoch_span_difference_seconds <= max(epoch_gaps)
):
    raise SystemExit("A39 GPU samples do not continuously cover the evaluator boundary")

cgroup = {}
for line in pathlib.Path(cgroup_name).read_text(encoding="utf-8").splitlines():
    if "=" in line:
        key, value = line.split("=", 1)
        cgroup[key] = value
if not (
    cgroup.get("slurm_job_id") == job_id
    and cgroup.get("process_cgroup_relative") == "unavailable"
    and cgroup.get("cgroup_v2_memory_status") == "unavailable"
):
    raise SystemExit("A39 cgroup-unavailable evidence differs")

preflight = load_json(preflight_name)
resource_admission = preflight.get("resource_admission", {})
if not (
    preflight.get("status") == "PASS"
    and preflight.get("experiment_id") == experiment_id
    and preflight.get("execution_id") == execution_id
    and resource_admission.get("hostname") == "ngu202"
    and resource_admission.get("partition") == "hgpu8"
    and resource_admission.get("gpu_name") == "NVIDIA A800-SXM4-80GB"
    and resource_admission.get("gpu_count") == 1
    and resource_admission.get("available_host_memory_bytes", 0) >= 2800353280
    and resource_admission.get("gpu_free_mib", 0) >= 4584
):
    raise SystemExit("A39 resource admission evidence differs")

result = load_json(result_name)
ledger = load_json(ledger_name)
manifest = load_json(manifest_name)
verification = load_json(verification_name)
expected_systems = [
    "knet_epoch75",
    "strict_zero_gain_knet",
    "same_forcing_open_loop",
    "default_noise_ukf",
    "sampled_search_ukf",
    "backpropagation_selected_ukf",
    "persistence",
    "second_order_autoregression",
]
if not (
    result.get("status") == "FORMAL_EVALUATION_COMPLETE"
    and result.get("experiment_id") == experiment_id
    and result.get("basin_id") == "09035800"
    and result.get("evaluation_period") == ["1989-10-01", "1999-09-30"]
    and result.get("warmup_days") == 365
    and result.get("leads_days") == [1, 2, 3]
    and result.get("systems") == expected_systems
    and result.get("metrics", {}).get("target_count_by_lead") == {"1": 3284, "2": 3284, "3": 3284}
):
    raise SystemExit("A39 formal evaluation scope differs")
if not (
    manifest.get("schema_version") == "daily_camels_knet_epoch75_formal_evaluation_manifest_v1"
    and manifest.get("experiment_id") == experiment_id
    and manifest.get("status") == "FORMAL_EVALUATION_COMPLETE"
    and manifest.get("configuration_sha256") == "573f5a7f58fec05445bd284c3ec550846b5c74900ea7459994ed778405d154ff"
    and manifest.get("files") == {
        "access_ledger.json": "7d01a372818603a2ab38d58ae10f6eb8c53894b08bb6d84d9375564e4507c757",
        "predictions.npz": "5ba30d6cc64d875e5621e65b33a41eaeaaee3cf3d7b06f19012dd09d86494de3",
        "result_summary.json": "0c5be30d87618ffe52584b48f9ad889568babede7ad9b414235eda98d7bff994",
    }
):
    raise SystemExit("A39 evaluation manifest differs")
decisions = result.get("decisions", {})
if not (
    decisions.get("capability_gate", {}).get("status") == "PASS"
    and decisions.get("capability_gate", {}).get("failed_conditions") == []
    and decisions.get("comparison_status") == "NO_DISCERNIBLE_ADVANTAGE"
    and decisions.get("scale_up_readiness") == "GO"
    and decisions.get("convergence_status") == "UNKNOWN_NOT_ESTABLISHED_BY_SINGLE_CHECKPOINT_FORMAL_EVALUATION"
):
    raise SystemExit("A39 scientific decisions differ")
if not (
    verification.get("technical_verification") == "PASS"
    and verification.get("experiment_id") == experiment_id
    and verification.get("basin_id") == "09035800"
    and verification.get("result_summary_sha256") == "0c5be30d87618ffe52584b48f9ad889568babede7ad9b414235eda98d7bff994"
    and verification.get("prediction_archive_sha256") == "5ba30d6cc64d875e5621e65b33a41eaeaaee3cf3d7b06f19012dd09d86494de3"
    and verification.get("prediction_semantic_sha256") == "1e619b1d815949e871fc63d5faa4375264e9f627a1d32a3b5399f5b9538f8b50"
    and verification.get("recomputed", {}).get("metrics") == result.get("metrics")
    and verification.get("recomputed", {}).get("comparisons") == result.get("comparisons")
    and verification.get("recomputed", {}).get("decisions") == result.get("decisions")
):
    raise SystemExit("A39 independent verification differs from the sealed result")
archive_access = ledger.get("evaluation_archive", {})
if not (
    ledger.get("experiment_id") == experiment_id
    and archive_access.get("open_count") == 1
    and archive_access.get("authorized_read_count") == 1
    and archive_access.get("array_reads") == {"dates_ns": 1, "forcing": 1, "target": 1}
    and ledger.get("optimizer_steps") == 0
    and ledger.get("training_events") == 0
    and ledger.get("checkpoint_writes") == 0
    and ledger.get("stored_baseline_prediction_reads") == 0
    and ledger.get("parameter_sha256_before") == "5a288a2ac6d2985253b37616d983d6dfaf0638b18169bba8fcd0439e5b922fce"
    and ledger.get("parameter_sha256_after") == ledger.get("parameter_sha256_before")
):
    raise SystemExit("A39 zero-training and one-time evaluation-access ledger differs")

resource_payload = {
    "schema_version": "daily_camels_knet_a39_terminal_resource_evidence_v1",
    "experiment_id": experiment_id,
    "execution_id": execution_id,
    "slurm_job_id": job_id,
    "slurm_main_state": main["state"],
    "slurm_main_exit_code": main["exit_code"],
    "cleanup_only_failure_class": "discrete_sampler_phase_at_evaluator_end",
    "evaluation_exit_code": 0,
    "independent_verification_exit_code": 0,
    "gpu_sampling": {
        "sample_count": len(gpu_rows),
        "first_timestamp": gpu_rows[0]["timestamp"].isoformat(timespec="milliseconds"),
        "last_timestamp": gpu_rows[-1]["timestamp"].isoformat(timespec="milliseconds"),
        "evaluation_start_epoch_seconds": evaluation_start,
        "evaluation_end_epoch_seconds": evaluation_end,
        "same_clock_epoch_last_sample_to_end_boundary_seconds": epoch_last_to_end_seconds,
        "same_clock_epoch_span_difference_seconds": epoch_span_difference_seconds,
        "raw_timestamp_last_sample_to_end_boundary_seconds_diagnostic": raw_timestamp_last_to_end_seconds,
        "maximum_raw_timestamp_gap_seconds": max(raw_gaps),
        "maximum_same_clock_epoch_gap_seconds": max(epoch_gaps),
        "continuous_evaluator_coverage": True,
        "gpu_name": gpu_rows[0]["name"],
        "gpu_uuid": gpu_rows[0]["uuid"],
        "total_memory_mib": gpu_rows[0]["total_mib"],
        "peak_used_memory_mib": max(row["used_mib"] for row in gpu_rows),
        "minimum_free_memory_mib": min(row["free_mib"] for row in gpu_rows),
        "peak_utilization_percent": max(row["utilization_percent"] for row in gpu_rows),
    },
    "host_memory": {
        "cgroup_memory_peak_status": "unavailable",
        "slurm_step_memory": step_memory,
        "slurm_max_rss_bytes": max((row["max_rss_bytes"] or 0) for row in step_memory),
        "slurm_max_vm_size_bytes": max((row["max_vm_size_bytes"] or 0) for row in step_memory),
    },
    "resource_admission": resource_admission,
    "completed_job_absent_from_user_active_queue": True,
    "squeue_exit_code": int(squeue_exit_text),
}
scientific_payload = {
    "schema_version": "daily_camels_knet_a39_terminal_scientific_evidence_v1",
    "experiment_id": experiment_id,
    "execution_id": execution_id,
    "slurm_job_id": job_id,
    "basin_id": result["basin_id"],
    "evaluation_period": result["evaluation_period"],
    "warmup_days": result["warmup_days"],
    "leads_days": result["leads_days"],
    "systems": result["systems"],
    "metrics": result["metrics"],
    "comparisons": result["comparisons"],
    "decisions": result["decisions"],
    "formal_evaluator_exit_code": 0,
    "independent_verifier_exit_code": 0,
    "independent_verification_status": verification["technical_verification"],
    "access_ledger": ledger,
    "result_summary_sha256": verification["result_summary_sha256"],
    "independent_verification_sha256": "735fb1facd3db4fbd6fdeb90a5c8a870f826ec2eb1d1927cae3a3af2f69f11bc",
    "prediction_file_sha256": verification["prediction_archive_sha256"],
    "prediction_semantic_sha256": verification["prediction_semantic_sha256"],
    "protected_evaluation_arrays_read_by_terminal_collector": 0,
    "prediction_arrays_read_by_terminal_collector": 0,
}
write_json(resource_output_name, resource_payload)
write_json(scientific_output_name, scientific_payload)
print(
    "SEQ102_A39_GPU_RESOURCE_SUMMARY "
    f"samples={len(gpu_rows)} max_raw_gap_seconds={max(raw_gaps):.3f} "
    f"max_epoch_gap_seconds={max(epoch_gaps)} epoch_last_to_end_seconds={epoch_last_to_end_seconds} "
    f"epoch_span_difference_seconds={epoch_span_difference_seconds} "
    f"raw_timestamp_last_to_end_seconds_diagnostic={raw_timestamp_last_to_end_seconds:.3f} "
    f"peak_gpu_mib={resource_payload['gpu_sampling']['peak_used_memory_mib']} "
    f"min_free_gpu_mib={resource_payload['gpu_sampling']['minimum_free_memory_mib']} "
    "continuous_evaluator_coverage=true"
)
print(
    "SEQ102_A39_HOST_MEMORY_RESOURCE_SUMMARY "
    f"slurm_max_rss_bytes={resource_payload['host_memory']['slurm_max_rss_bytes']} "
    f"slurm_max_vm_size_bytes={resource_payload['host_memory']['slurm_max_vm_size_bytes']} "
    "cgroup_peak_status=unavailable slurm_step_accounting_fallback=true"
)
metrics = result["metrics"]
for system in expected_systems:
    for lead in ("1", "2", "3"):
        print(
            "SEQ102_A39_METRIC "
            f"basin=09035800 system={system} lead_days={lead} origins={metrics['target_count_by_lead'][lead]} "
            f"nse={metrics['nse_by_system_and_lead'][system][lead]:.17g} "
            f"mse={metrics['mse_by_system_and_lead'][system][lead]:.17g}"
        )
print(
    "SEQ102_A39_INDEPENDENT_TERMINAL_VALIDATION "
    "capability=PASS comparison=NO_DISCERNIBLE_ADVANTAGE scale_up=GO "
    "convergence=UNKNOWN_NOT_ESTABLISHED_BY_SINGLE_CHECKPOINT_FORMAL_EVALUATION "
    "one_basin_only=true protected_array_reads=0 prediction_array_reads=0"
)
PY

COLLECTOR_ACTUAL_SHA256="$(sha256sum "${COLLECTOR_SOURCE}" | awk '{print $1}')"
COLLECTOR_ACTUAL_SIZE="$(stat -c '%s' "${COLLECTOR_SOURCE}")"
CMD_ACTUAL_SHA256="$(sha256sum "${CMD_SOURCE}" | awk '{print $1}')"
CMD_ACTUAL_SIZE="$(stat -c '%s' "${CMD_SOURCE}")"
DISPATCH_ACTUAL_SHA256="$(sha256sum "${DISPATCH_SNAPSHOT}" | awk '{print $1}')"
DISPATCH_ACTUAL_SIZE="$(stat -c '%s' "${DISPATCH_SNAPSHOT}")"

cat > "${EVIDENCE_ROOT}/artifact_identities.txt" <<EOF
result_summary_sha256=${RESULT_SUMMARY_SHA256}
access_ledger_sha256=${ACCESS_LEDGER_SHA256}
independent_verification_sha256=${INDEPENDENT_VERIFICATION_SHA256}
predictions_sha256=${PREDICTIONS_SHA256}
predictions_size=${PREDICTIONS_SIZE}
checkpoint_sha256=${CHECKPOINT_SHA256}
checkpoint_size=${CHECKPOINT_SIZE}
configuration_sha256=${CONFIG_SHA256}
slurm_entry_sha256=${SLURM_ENTRY_SHA256}
evaluation_manifest_sha256=${EVALUATION_MANIFEST_SHA256}
sequence_100_result_sha256=${RESULT100_SHA256}
sequence_101_failed_result_sha256=${RESULT101_SHA256}
terminal_collector_sha256=${COLLECTOR_ACTUAL_SHA256}
terminal_collector_size=${COLLECTOR_ACTUAL_SIZE}
mailbox_command_sha256=${CMD_ACTUAL_SHA256}
mailbox_command_size=${CMD_ACTUAL_SIZE}
dispatch_snapshot_sha256=${DISPATCH_ACTUAL_SHA256}
dispatch_snapshot_size=${DISPATCH_ACTUAL_SIZE}
protected_evaluation_arrays_in_archive=0
prediction_arrays_in_archive=0
EOF

if find "${EVIDENCE_ROOT}" -type l -print -quit | grep -q .; then
  echo "terminal evidence staging contains a symbolic link" >&2
  exit 48
fi
if find "${EVIDENCE_ROOT}" \( -iname '*.npz' -o -iname '*.pt' -o -iname '*heldout*' -o -iname '*reserved*' \) -print -quit | grep -q .; then
  echo "terminal evidence staging contains a forbidden data member" >&2
  exit 48
fi

FILES_BEFORE_TERMINAL_MARKER="$(find "${EVIDENCE_ROOT}" -type f | wc -l | tr -d '[:space:]')"
DIRECTORIES_IN_EVIDENCE="$(find "${EVIDENCE_ROOT}" -mindepth 1 -type d | wc -l | tr -d '[:space:]')"
EXPECTED_ARCHIVE_FILE_COUNT="$((FILES_BEFORE_TERMINAL_MARKER + 2))"
EXPECTED_ARCHIVE_MEMBER_COUNT="$((1 + DIRECTORIES_IN_EVIDENCE + EXPECTED_ARCHIVE_FILE_COUNT))"
cat > "${EVIDENCE_ROOT}/terminal_status.txt" <<EOF
experiment_id=${EXPERIMENT_ID}
execution_id=${EXECUTION_ID}
slurm_job_id=${JOB_ID}
slurm_main_state=FAILED
slurm_main_exit_code=72:0
slurm_node=ngu202
slurm_partition=hgpu8
gpu_name=NVIDIA A800-SXM4-80GB
formal_evaluator_exit_code=0
independent_verifier_exit_code=0
cleanup_only_failure_class=discrete_sampler_phase_at_evaluator_end
runtime_evaluation_lock_present=false
persistent_submission_lock_present=true
expected_archive_file_count=${EXPECTED_ARCHIVE_FILE_COUNT}
expected_archive_member_count=${EXPECTED_ARCHIVE_MEMBER_COUNT}
forbidden_archive_member_count=0
protected_evaluation_array_reads_by_collector=0
prediction_array_reads_by_collector=0
EOF

MANIFEST="${EVIDENCE_ROOT}/manifest.sha256"
(
  cd "${EVIDENCE_ROOT}"
  find . -type f ! -name 'manifest.sha256' -print0 \
    | sort -z \
    | xargs -0 sha256sum > "${MANIFEST}"
)
[[ "$(find "${EVIDENCE_ROOT}" -type f | wc -l | tr -d '[:space:]')" == "${EXPECTED_ARCHIVE_FILE_COUNT}" ]] || {
  echo "terminal evidence file count differs" >&2
  exit 49
}

ARCHIVE_TEMP="$(mktemp "${ARCHIVE}.tmp.XXXXXXXX")"
[[ -f "${ARCHIVE_TEMP}" && ! -L "${ARCHIVE_TEMP}" ]] || { echo "unsafe archive temporary file" >&2; exit 49; }
(
  cd "${STAGING_ROOT}"
  tar --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -cf - "$(basename "${EVIDENCE_ROOT}")" | gzip -n > "${ARCHIVE_TEMP}"
)
[[ -s "${ARCHIVE_TEMP}" && ! -L "${ARCHIVE_TEMP}" ]] || { echo "terminal archive build failed" >&2; exit 49; }
gzip -t -- "${ARCHIVE_TEMP}" || { echo "terminal archive gzip validation failed" >&2; exit 49; }

ARCHIVE_MEMBERS="${STAGING_ROOT}/archive_members.txt"
tar -tzf "${ARCHIVE_TEMP}" > "${ARCHIVE_MEMBERS}"
[[ -s "${ARCHIVE_MEMBERS}" ]] || { echo "terminal archive member list is empty" >&2; exit 49; }
ARCHIVE_MEMBER_COUNT="$(wc -l < "${ARCHIVE_MEMBERS}" | tr -d '[:space:]')"
[[ "${ARCHIVE_MEMBER_COUNT}" == "${EXPECTED_ARCHIVE_MEMBER_COUNT}" ]] || {
  echo "terminal archive member count differs" >&2
  exit 49
}
FORBIDDEN_ARCHIVE_MEMBER_COUNT=0
while IFS= read -r member; do
  [[ -n "${member}" ]] || { echo "terminal archive contains an empty member name" >&2; exit 49; }
  case "${member}" in
    /*|../*|*/../*|*/..) echo "terminal archive contains an unsafe path" >&2; exit 49 ;;
  esac
  member_lower="${member,,}"
  case "${member_lower}" in
    *.npz|*.npy|*.pt|*heldout*|*reserved*) FORBIDDEN_ARCHIVE_MEMBER_COUNT=$((FORBIDDEN_ARCHIVE_MEMBER_COUNT + 1)) ;;
  esac
done < "${ARCHIVE_MEMBERS}"
[[ "${FORBIDDEN_ARCHIVE_MEMBER_COUNT}" == "0" ]] || { echo "terminal archive contains forbidden members" >&2; exit 49; }

VERIFY_ROOT="${STAGING_ROOT}/archive-verify"
mkdir -p "${VERIFY_ROOT}"
tar -xzf "${ARCHIVE_TEMP}" -C "${VERIFY_ROOT}" --no-same-owner --no-same-permissions
VERIFY_EVIDENCE_ROOT="${VERIFY_ROOT}/$(basename "${EVIDENCE_ROOT}")"
[[ -d "${VERIFY_EVIDENCE_ROOT}" && ! -L "${VERIFY_EVIDENCE_ROOT}" ]] || { echo "terminal archive extraction root differs" >&2; exit 49; }
if find "${VERIFY_EVIDENCE_ROOT}" -type l -print -quit | grep -q .; then
  echo "terminal archive contains a symbolic link" >&2
  exit 49
fi
if find "${VERIFY_EVIDENCE_ROOT}" -mindepth 1 ! -type f ! -type d -print -quit | grep -q .; then
  echo "terminal archive contains a non-regular member" >&2
  exit 49
fi
[[ "$(find "${VERIFY_EVIDENCE_ROOT}" -type f | wc -l | tr -d '[:space:]')" == "${EXPECTED_ARCHIVE_FILE_COUNT}" ]] || {
  echo "extracted terminal archive file count differs" >&2
  exit 49
}
(
  cd "${VERIFY_EVIDENCE_ROOT}"
  sha256sum -c manifest.sha256 >/dev/null
) || { echo "terminal archive manifest validation failed" >&2; exit 49; }

[[ ! -e "${RUNTIME_LOCK}" && ! -L "${RUNTIME_LOCK}" ]] || { echo "A39 evaluation lock reappeared before publish" >&2; exit 50; }
require_regular_identity "${LOCK_ROOT}/owner.json" "${SUBMISSION_OWNER_SHA256}" "${SUBMISSION_OWNER_SIZE}" "pre-publish A39 submission owner"
require_regular_identity "${LOCK_ROOT}/bound.json" "${SUBMISSION_BOUND_SHA256}" "${SUBMISSION_BOUND_SIZE}" "pre-publish A39 bound submission owner"
require_regular_identity "${COLLECTOR_SOURCE}" "${COLLECTOR_ACTUAL_SHA256}" "${COLLECTOR_ACTUAL_SIZE}" "pre-publish A39 terminal collector"
require_regular_identity "${CMD_SOURCE}" "${CMD_ACTUAL_SHA256}" "${CMD_ACTUAL_SIZE}" "pre-publish A39 mailbox command"
require_regular_identity "${DISPATCH_SNAPSHOT}" "${DISPATCH_ACTUAL_SHA256}" "${DISPATCH_ACTUAL_SIZE}" "pre-publish A39 dispatch snapshot"
require_regular_identity "${PREDICTIONS}" "${PREDICTIONS_SHA256}" "${PREDICTIONS_SIZE}" "pre-publish A39 opaque prediction artifact"
require_regular_identity "${CHECKPOINT}" "${CHECKPOINT_SHA256}" "${CHECKPOINT_SIZE}" "pre-publish epoch 75 checkpoint"
require_regular_identity "${CONFIG}" "${CONFIG_SHA256}" "${CONFIG_SIZE}" "pre-publish A39 frozen configuration"
require_regular_identity "${SLURM_ENTRY}" "${SLURM_ENTRY_SHA256}" "${SLURM_ENTRY_SIZE}" "pre-publish A39 Slurm entry"
cmp -s -- "${CMD_SOURCE}" "${DISPATCH_SNAPSHOT}" || { echo "A39 mailbox command changed before publish" >&2; exit 50; }
[[ ! -e "${ARCHIVE}" && ! -L "${ARCHIVE}" ]] || { echo "terminal evidence archive appeared before publish" >&2; exit 50; }
ln -- "${ARCHIVE_TEMP}" "${ARCHIVE}" || { echo "terminal evidence no-overwrite publish failed" >&2; exit 50; }
ARCHIVE_PUBLISHED=1
[[ -f "${ARCHIVE}" && ! -L "${ARCHIVE}" && "${ARCHIVE}" -ef "${ARCHIVE_TEMP}" ]] || { echo "published archive identity differs" >&2; exit 50; }
ARCHIVE_SHA256="$(sha256sum "${ARCHIVE}" | awk '{print $1}')"
ARCHIVE_SIZE="$(stat -c '%s' "${ARCHIVE}")"
[[ "${ARCHIVE_SHA256}" == "$(sha256sum "${ARCHIVE_TEMP}" | awk '{print $1}')" ]] || { echo "published archive hash differs" >&2; exit 50; }
[[ "${ARCHIVE_SIZE}" == "$(stat -c '%s' "${ARCHIVE_TEMP}")" ]] || { echo "published archive size differs" >&2; exit 50; }
[[ ! -e "${RUNTIME_LOCK}" && ! -L "${RUNTIME_LOCK}" ]] || { echo "A39 evaluation lock reappeared after publish" >&2; exit 50; }
require_regular_identity "${LOCK_ROOT}/owner.json" "${SUBMISSION_OWNER_SHA256}" "${SUBMISSION_OWNER_SIZE}" "post-publish A39 submission owner"
require_regular_identity "${LOCK_ROOT}/bound.json" "${SUBMISSION_BOUND_SHA256}" "${SUBMISSION_BOUND_SIZE}" "post-publish A39 bound submission owner"
require_regular_identity "${COLLECTOR_SOURCE}" "${COLLECTOR_ACTUAL_SHA256}" "${COLLECTOR_ACTUAL_SIZE}" "post-publish A39 terminal collector"
require_regular_identity "${CMD_SOURCE}" "${CMD_ACTUAL_SHA256}" "${CMD_ACTUAL_SIZE}" "post-publish A39 mailbox command"
require_regular_identity "${DISPATCH_SNAPSHOT}" "${DISPATCH_ACTUAL_SHA256}" "${DISPATCH_ACTUAL_SIZE}" "post-publish A39 dispatch snapshot"
require_regular_identity "${PREDICTIONS}" "${PREDICTIONS_SHA256}" "${PREDICTIONS_SIZE}" "post-publish A39 opaque prediction artifact"
require_regular_identity "${CHECKPOINT}" "${CHECKPOINT_SHA256}" "${CHECKPOINT_SIZE}" "post-publish epoch 75 checkpoint"
require_regular_identity "${CONFIG}" "${CONFIG_SHA256}" "${CONFIG_SIZE}" "post-publish A39 frozen configuration"
require_regular_identity "${SLURM_ENTRY}" "${SLURM_ENTRY_SHA256}" "${SLURM_ENTRY_SIZE}" "post-publish A39 Slurm entry"
cmp -s -- "${CMD_SOURCE}" "${DISPATCH_SNAPSHOT}" || { echo "A39 mailbox command changed after publish" >&2; exit 50; }

rm -f -- "${ARCHIVE_TEMP}"
ARCHIVE_TEMP=""
ARCHIVE_PUBLISHED=0
cleanup
trap - EXIT

printf 'SEQ102_A39_TERMINAL_COLLECTED experiment_id=%s execution_id=%s job_id=%s slurm_main_state=FAILED slurm_main_exit=72:0 node=ngu202 partition=hgpu8 gpu=%s archive=%s archive_size=%s archive_sha256=%s archive_member_count=%s forbidden_archive_member_count=0 evaluator_exit=0 independent_verifier_exit=0 runtime_evaluation_lock_present=false persistent_submission_lock_present=true protected_array_reads=0 prediction_array_reads=0 cleanup_only_failure_class=discrete_sampler_phase_at_evaluator_end\n' \
  "${EXPERIMENT_ID}" "${EXECUTION_ID}" "${JOB_ID}" "NVIDIA_A800-SXM4-80GB" "${ARCHIVE}" \
  "${ARCHIVE_SIZE}" "${ARCHIVE_SHA256}" "${ARCHIVE_MEMBER_COUNT}"
