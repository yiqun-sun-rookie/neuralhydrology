#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL="kalmannet-daily-camels"
EXPERIMENT_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_V1_20260831_A39"
EXECUTION_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL5_SEQ98"
SUBMISSION_TOKEN="bd450dbffdfdfc6ffe570e6ceba9f48e99a786d794a0db5bb68a79d3f49ea6b2"
JOB_NAME="daily-knet-a39-s98"
SUBMISSION_COMMENT="${EXECUTION_ID}"
RUN_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation5_20260831"
SOURCE_ROOT="${RUN_ROOT}/source_A39_formal_evaluation_seq98"
EXTERNAL_EVIDENCE_ROOT="${RUN_ROOT}/external_evidence"
STATUS_ROOT="${RUN_ROOT}/status"
LOCK_ROOT="${STATUS_ROOT}/locks/${EXECUTION_ID}.submission.lock"
OWNER_JSON="${LOCK_ROOT}/owner.json"
BOUND_JSON="${LOCK_ROOT}/bound.json"
JOB_ID_FILE="${STATUS_ROOT}/submitted_job_id.txt"
PAYLOAD_ROOT="${MAILBOX_ROOT}/payload/${CHANNEL}/a39_epoch75_single_basin_formal_evaluation_eval5_seq98_20260831"
ARCHIVE="${PAYLOAD_ROOT}/${EXPERIMENT_ID}.tar.gz"
OUTER_MANIFEST="${PAYLOAD_ROOT}/bundle_manifest.sha256.json"
ARCHIVE_SHA256="8c4ac568c808ad9d0a58177fbb7ab5a091cfe534c4363146104db56c52ffe5de"
ARCHIVE_SIZE="231540"
OUTER_MANIFEST_SHA256="04bb82239440291903e653ee1d1c90d7f4b3a72a7fc029bcfdbf15aa13440924"
OUTER_MANIFEST_SIZE="2627"
INTERNAL_MANIFEST_SHA256="daffb66462669be33733c8b69a1d5b39de2d86862efa900dbf46371e3eee234c"
INTERNAL_MANIFEST_SIZE="10653"
ARCHIVE_MEMBER_COUNT="39"
REGISTERED_MEMBER_COUNT="38"
SLURM_REL="hpc/daily_camels_knet_formal_evaluation/submit_evaluation_gpu.slurm"
SLURM_SHA256="c499f3175da8c36f553e99c09c88e417820c0292d4be1fea1382108ab6770276"
SLURM_SIZE="20763"
PREFLIGHT_REL="hpc/daily_camels_knet_formal_evaluation/preflight.py"
PREFLIGHT_SHA256="fc6aa87375085dd725ae29dbc636f435bd72c25ec318d83e5ae1e12e19e22cf5"
PREFLIGHT_SIZE="41567"
RESULT85="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_85.txt"
RESULT85_SHA256="a3ef9061e9b9634c10792700407c077d4e34529f58dc6052a68eea5594e10a2a"
RESULT85_SIZE="3789"
RESULT88="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_88.txt"
RESULT88_SHA256="3d275a97832907159085ee83a20b2649cf9e0a8e69ccfbe4684a288dca748bfb"
RESULT88_SIZE="6736"
RESULT90="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_90.txt"
RESULT90_SHA256="dacc0fb4c28ac48942f892df3015b7f92f0b2c9df9e04cf387534d55ac93d74d"
RESULT90_SIZE="2092"
RESULT91="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_91.txt"
RESULT91_SHA256="8a6790e87027a45160a21a9c3cc45a009702e88785da49dcaf6c624ffdd3fb38"
RESULT91_SIZE="1276"
RESULT92="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_92.txt"
RESULT92_SHA256="f15f30f8587be56c69c0f76fb7f6b77f5c9b2a9963d6d6a5fd46fbb4d71b5c4e"
RESULT92_SIZE="525"
RESULT93="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_93.txt"
RESULT93_SHA256="8270074aacfa7bef826cd47ada87e352a4bb44529fdefbed19dcb3b080d2d1a5"
RESULT93_SIZE="8837"
RESULT94="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_94.txt"
RESULT94_SHA256="9e5016900324873d62f3e43601ef59b48f4002a900c4bcc57e53b82eccab6013"
RESULT94_SIZE="1519"
RESULT96="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_96.txt"
RESULT96_SHA256="1a3c0e598d4368e01e1cecdf2f5ab7781e4ce16802a372650eca72b3e514d1a0"
RESULT96_SIZE="525"
RESULT97="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_97.txt"
RESULT97_SHA256="1348ab73108bfb5b3c7f9dc69aefe610c55c82d46d8ad42f91cffd168b3fb104"
RESULT97_SIZE="23453"
RECONSTRUCTED_SOURCE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_terminal_evidence_reconstruct_seq89_20260831/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_RECONSTRUCT_SEQ89.tar.gz"
RECONSTRUCTED_RUNTIME="${EXTERNAL_EVIDENCE_ROOT}/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_RECONSTRUCT_SEQ89.tar.gz"
RECONSTRUCTED_SHA256="89975d9d69d477d625ae11713a96edf618cb6189284e280f3008bfe0f785676d"
RECONSTRUCTED_SIZE="13900887"
RECEIPT_SOURCE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_terminal_evidence_verify_seq90_20260831/member_identity_verification.json"
RECEIPT_RUNTIME="${EXTERNAL_EVIDENCE_ROOT}/member_identity_verification.json"
RECEIPT_SHA256="ac2fc24c15edb7b9d5e22ced035141c4fa256e79f8067ea9225be9613abe8f56"
RECEIPT_SIZE="1278"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_file() {
  local path="$1" expected_sha="$2" expected_size="$3" label="$4"
  [[ -f "${path}" && ! -L "${path}" ]] || {
    echo "${label} absent, non-regular, or symbolic" >&2
    exit 40
  }
  [[ "$(stat -c '%s' "${path}")" == "${expected_size}" ]] || {
    echo "${label} size differs" >&2
    exit 41
  }
  [[ "$(sha256_file "${path}")" == "${expected_sha}" ]] || {
    echo "${label} SHA-256 differs" >&2
    exit 42
  }
}

verify_outer_manifest() {
  python -B -S - \
    "${OUTER_MANIFEST}" \
    "${EXPERIMENT_ID}" \
    "$(basename "${ARCHIVE}")" \
    "${ARCHIVE_SHA256}" \
    "${ARCHIVE_SIZE}" \
    "${REGISTERED_MEMBER_COUNT}" \
    "${INTERNAL_MANIFEST_SHA256}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
experiment_id, archive_name, archive_sha, archive_size, registered_count, internal_sha = sys.argv[2:]
payload = json.loads(path.read_text(encoding="utf-8"))
expected = {
    "schema_version": "daily_camels_knet_formal_evaluation_hpc_archive_v1",
    "experiment_id": experiment_id,
    "archive_name": archive_name,
    "archive_sha256": archive_sha,
    "archive_size": int(archive_size),
    "member_count": int(registered_count),
    "internal_manifest_sha256": internal_sha,
    "checkpoint_member_count": 0,
    "historical_evaluation_array_member_count": 0,
}
for key, expected_value in expected.items():
    if payload.get(key) != expected_value:
        raise SystemExit(f"outer manifest differs at {key}")
PY
}

query_scheduler() {
  local prefix="$1" squeue_rc sacct_rc
  set +e
  squeue -h -u "${EXPECTED_USER}" -o '%A|%j|%P|%T|%u|%k|%Z' \
    > "${prefix}.squeue" 2> "${prefix}.squeue.err"
  squeue_rc=$?
  sacct -n -X -u "${EXPECTED_USER}" -S 2026-08-31 \
    --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList -P \
    > "${prefix}.sacct" 2> "${prefix}.sacct.err"
  sacct_rc=$?
  set -e
  [[ "${squeue_rc}" == 0 && "${sacct_rc}" == 0 ]] || {
    echo "scheduler uniqueness query failed closed" >&2
    return 70
  }
}

matching_ids() {
  python -B -S - \
    "$1.squeue" \
    "$1.sacct" \
    "${JOB_NAME}" \
    "${EXPECTED_USER}" \
    "${SUBMISSION_COMMENT}" \
    "${SOURCE_ROOT}" <<'PY'
import pathlib
import sys

squeue_path = pathlib.Path(sys.argv[1])
sacct_path = pathlib.Path(sys.argv[2])
job_name, expected_user, comment, source_root = sys.argv[3:]
job_ids = set()
for line in squeue_path.read_text(encoding="utf-8").splitlines():
    parts = line.split("|")
    if (
        len(parts) >= 7
        and parts[1] == job_name
        and parts[4] == expected_user
        and parts[5] == comment
        and parts[6] == source_root
    ):
        job_ids.add(parts[0])
for line in sacct_path.read_text(encoding="utf-8").splitlines():
    parts = line.split("|")
    if (
        len(parts) >= 8
        and parts[1] == job_name
        and parts[2] == expected_user
        and parts[3] == "hgpu8"
    ):
        job_ids.add(parts[0])
for value in sorted(job_ids):
    if not value.isdigit():
        raise SystemExit("non-numeric matching Slurm identity")
    print(value)
PY
}

active_a39_ids() {
  python -B -S - "$1.squeue" "${EXPECTED_USER}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expected_user = sys.argv[2]
for line in path.read_text(encoding="utf-8").splitlines():
    parts = line.split("|")
    if (
        len(parts) >= 7
        and parts[1].startswith("daily-knet-a39-")
        and parts[4] == expected_user
    ):
        job_id = parts[0]
        if not job_id.isdigit():
            raise SystemExit("non-numeric active A39 Slurm identity")
        print(job_id)
PY
}

validate_prepared_owner() {
  python -B -S - \
    "${OWNER_JSON}" \
    "${EXPERIMENT_ID}" \
    "${EXECUTION_ID}" \
    "${SUBMISSION_TOKEN}" \
    "${ARCHIVE_SHA256}" \
    "${SLURM_SHA256}" \
    "${RESULT85_SHA256}" \
    "${RESULT88_SHA256}" \
    "${RESULT90_SHA256}" \
    "${RESULT91_SHA256}" \
    "${RESULT92_SHA256}" \
    "${RESULT93_SHA256}" \
    "${RESULT94_SHA256}" \
    "${RESULT96_SHA256}" \
    "${RESULT97_SHA256}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.is_file() or path.is_symlink():
    raise SystemExit("PREPARED owner is absent, non-regular, or symbolic")
payload = json.loads(path.read_text(encoding="utf-8"))
(
    experiment_id,
    execution_id,
    token,
    archive_sha,
    slurm_sha,
    result85_sha,
    result88_sha,
    result90_sha,
    result91_sha,
    result92_sha,
    result93_sha,
    result94_sha,
    result96_sha,
    result97_sha,
) = sys.argv[2:]
expected = {
    "experiment_id": experiment_id,
    "execution_id": execution_id,
    "submission_token": token,
    "state": "PREPARED",
    "persistent": True,
    "evaluation_only": True,
    "archive_sha256": archive_sha,
    "slurm_sha256": slurm_sha,
    "eval1_diagnostic_result85_sha256": result85_sha,
    "eval2_diagnostic_result88_sha256": result88_sha,
    "member_identity_result90_sha256": result90_sha,
    "eval3_submission_result91_sha256": result91_sha,
    "eval3_terminal_result92_sha256": result92_sha,
    "eval3_diagnostic_result93_sha256": result93_sha,
    "eval4_submission_result94_sha256": result94_sha,
    "eval4_terminal_result96_sha256": result96_sha,
    "eval4_diagnostic_result97_sha256": result97_sha,
    "prior_failed_job_id": "216974",
    "prior_failure_class": "recoverable_checkpoint_identity_canonicalization_mismatch",
    "mailbox_sequence": 98,
}
for key, expected_value in expected.items():
    if payload.get(key) != expected_value:
        raise SystemExit(f"PREPARED owner differs at {key}")
PY
}

validate_bound_if_present() {
  local expected_job_id="$1"
  if [[ ! -e "${BOUND_JSON}" && ! -L "${BOUND_JSON}" ]]; then
    return 0
  fi
  python -B -S - \
    "${BOUND_JSON}" \
    "${EXPERIMENT_ID}" \
    "${EXECUTION_ID}" \
    "${SUBMISSION_TOKEN}" \
    "${expected_job_id}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.is_file() or path.is_symlink():
    raise SystemExit("Slurm-written BOUND evidence is non-regular or symbolic")
payload = json.loads(path.read_text(encoding="utf-8"))
experiment_id, execution_id, token, job_id = sys.argv[2:]
expected = {
    "experiment_id": experiment_id,
    "execution_id": execution_id,
    "submission_token": token,
    "slurm_job_id": job_id,
    "state": "BOUND",
    "persistent": True,
    "evaluation_only": True,
}
for key, expected_value in expected.items():
    if payload.get(key) != expected_value:
        raise SystemExit(f"Slurm-written BOUND evidence differs at {key}")
PY
}

record_job_id() {
  local job_id="$1"
  [[ "${job_id}" =~ ^[0-9]+$ ]] || {
    echo "refusing non-numeric Slurm job identity" >&2
    exit 71
  }
  python -B -S - "${JOB_ID_FILE}" "${job_id}" <<'PY'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
job_id = sys.argv[2]
if path.exists() or path.is_symlink():
    if not path.is_file() or path.is_symlink():
        raise SystemExit("job-id evidence is non-regular or symbolic")
    if path.read_text(encoding="utf-8").strip() != job_id:
        raise SystemExit("job-id evidence differs")
else:
    with path.open("x", encoding="utf-8") as handle:
        handle.write(job_id + "\n")
        handle.flush()
        os.fsync(handle.fileno())
PY
}

recover_only() {
  local temporary_directory count bound_job_id existing_job_id
  local -a recovered_ids
  temporary_directory="$(mktemp -d /tmp/a39-seq98-recover.XXXXXX)"
  query_scheduler "${temporary_directory}/snapshot"
  mapfile -t recovered_ids < <(matching_ids "${temporary_directory}/snapshot")
  count="${#recovered_ids[@]}"

  if [[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]]; then
    existing_job_id="$(tr -d '\r\n' < "${JOB_ID_FILE}")"
    [[ "${existing_job_id}" =~ ^[0-9]+$ ]] || {
      echo "recorded Slurm job identity is invalid" >&2
      exit 71
    }
    [[ "${count}" == 1 && "${recovered_ids[0]}" == "${existing_job_id}" ]] || {
      echo "recorded job does not have exactly one scheduler identity; no sbatch retry permitted" >&2
      exit 72
    }
    record_job_id "${existing_job_id}"
    validate_bound_if_present "${existing_job_id}"
    echo "SEQ98_A39_RECOVERED_RECORDED job_id=${existing_job_id}"
    return 0
  fi

  if [[ -f "${BOUND_JSON}" && ! -L "${BOUND_JSON}" ]]; then
    bound_job_id="$(python -B -S -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["slurm_job_id"])' "${BOUND_JSON}")"
    [[ "${bound_job_id}" =~ ^[0-9]+$ ]] || {
      echo "Slurm-written BOUND job identity is invalid" >&2
      exit 71
    }
    [[ "${count}" == 1 && "${recovered_ids[0]}" == "${bound_job_id}" ]] || {
      echo "BOUND job does not have exactly one scheduler identity; no sbatch retry permitted" >&2
      exit 72
    }
    validate_bound_if_present "${bound_job_id}"
    record_job_id "${bound_job_id}"
    echo "SEQ98_A39_RECOVERED_BOUND job_id=${bound_job_id}"
    return 0
  fi

  [[ "${count}" == 1 ]] || {
    echo "PREPARED submission has ${count} recoverable exact jobs; no sbatch retry permitted" >&2
    exit 72
  }
  record_job_id "${recovered_ids[0]}"
  echo "SEQ98_A39_RECOVERED_AFTER_AMBIGUOUS_RECEIPT job_id=${recovered_ids[0]}"
}

[[ "$(id -un)" == "${EXPECTED_USER}" && "${USER-}" == "${EXPECTED_USER}" ]] || {
  echo "fixed user differs" >&2
  exit 43
}
require_file "${RESULT85}" "${RESULT85_SHA256}" "${RESULT85_SIZE}" "sequence-85 eval1 terminal diagnostic"
for expected in \
  'required A39 bundle member is absent, non-regular, or symbolic: /data1/home/sunyiq/hpc_mailbox/bundle_manifest.json' \
  'SEQ85_PATH_STATE evaluation_exists=false verification_exists=false runtime_lock_exists=false submission_lock_exists=true' \
  'SEQ85_A39_TERMINAL_DIAGNOSTIC_COMPLETE job_id=216551'; do
  grep -Fq "${expected}" "${RESULT85}" || {
    echo "sequence-85 eval1 diagnostic differs at: ${expected}" >&2
    exit 43
  }
done
require_file "${RESULT88}" "${RESULT88_SHA256}" "${RESULT88_SIZE}" "sequence-88 eval2 terminal diagnostic"
for expected in \
  'external A39 artifact is absent, non-regular, or symbolic: /data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ82.tar.gz' \
  'DIRECTORY_ABSENT path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation2_20260831/evaluation' \
  'DIRECTORY_ABSENT path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation2_20260831/verification' \
  'SEQ88_A39_TERMINAL_DIAGNOSTIC_COMPLETE job_id=216691'; do
  grep -Fq "${expected}" "${RESULT88}" || {
    echo "sequence-88 eval2 diagnostic differs at: ${expected}" >&2
    exit 43
  }
done
require_file "${RESULT90}" "${RESULT90_SHA256}" "${RESULT90_SIZE}" "sequence-90 member-identity result"
grep -Fq 'member_count=33 reserved_member_count=0' "${RESULT90}" || {
  echo "sequence-90 member inventory differs" >&2
  exit 43
}
grep -Fq 'member_content_identity_verified=true container_byte_identity_reproduced=false evaluation_array_reads=0 formal_evaluation_outputs_created=0' "${RESULT90}" || {
  echo "sequence-90 content-identity verdict differs" >&2
  exit 43
}
require_file "${RESULT91}" "${RESULT91_SHA256}" "${RESULT91_SIZE}" "sequence-91 eval3 submission result"
grep -Fq 'SEQ91_A39_FORMAL_EVALUATION_SUBMITTED experiment_id=DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_V1_20260831_A39 execution_id=DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL3_SEQ91 job_id=216847' "${RESULT91}" || {
  echo "sequence-91 eval3 submission identity differs" >&2
  exit 43
}
for expected in \
  'SEQ91_A39_STATIC_CHECK_PASS' \
  'SEQ91_A39_DISPATCH_VERIFIED' \
  'archive_sha256=bc4119187c70183dd90d599f7871e2e8033b4005c6be06b5a2ce4a5b74addca6' \
  'slurm_sha256=09ec7afc08924a60dda7694359cb2143675cbf11e6b8cd1274365b7f0b524961' \
  'preflight_sha256=4d67e635544389118787ebea6972abc4639ec6cb4ba66b8db14a52d57cd57bc6' \
  'source_root=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation3_20260831/source_A39_formal_evaluation_seq91'; do
  grep -Fq "${expected}" "${RESULT91}" || {
    echo "sequence-91 eval3 submission evidence differs at: ${expected}" >&2
    exit 43
  }
done
require_file "${RESULT92}" "${RESULT92_SHA256}" "${RESULT92_SIZE}" "sequence-92 eval3 terminal status"
grep -Fq '216847|daily-knet-a39-s91|sunyiq|hgpu8|FAILED|2:0|00:00:04|' "${RESULT92}" || {
  echo "sequence-92 eval3 terminal state differs" >&2
  exit 43
}
grep -Fq 'SEQ92_A39_STATUS_QUERY_COMPLETE job_id=216847 squeue_exit=1 sacct_exit=0' "${RESULT92}" || {
  echo "sequence-92 eval3 accounting completion differs" >&2
  exit 43
}
require_file "${RESULT93}" "${RESULT93_SHA256}" "${RESULT93_SIZE}" "sequence-93 eval3 terminal diagnostic"
for expected in \
  'FILE_BEGIN label=slurm_stderr path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation3_20260831/logs/evaluation-216847.err size=133 sha256=51974b51ca8d9a4dcaf354cf680166580528b84e573d3e60b06b44418e034ade' \
  'A39 formal-evaluation preflight failed: allocation must contain exactly one GPU' \
  'DIRECTORY_ABSENT path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation3_20260831/evaluation' \
  'DIRECTORY_ABSENT path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation3_20260831/verification' \
  'DIRECTORY_ABSENT path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation3_20260831/status/locks/DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL3_SEQ91.evaluation.lock' \
  'FILE_ABSENT label=preflight_report' \
  'FILE_ABSENT label=result_summary' \
  'FILE_ABSENT label=access_ledger' \
  'FILE_ABSENT label=independent_verification' \
  'SEQ93_A39_TERMINAL_DIAGNOSTIC_COMPLETE job_id=216847'; do
  grep -Fq "${expected}" "${RESULT93}" || {
    echo "sequence-93 eval3 diagnostic differs at: ${expected}" >&2
    exit 43
  }
done
require_file "${RESULT94}" "${RESULT94_SHA256}" "${RESULT94_SIZE}" "sequence-94 eval4 submission result"
grep -Fq 'SEQ94_A39_FORMAL_EVALUATION_SUBMITTED experiment_id=DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_V1_20260831_A39 execution_id=DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL4_SEQ94 job_id=216974' "${RESULT94}" || {
  echo "sequence-94 eval4 submission identity differs" >&2
  exit 43
}
for expected in \
  'SEQ94_A39_STATIC_CHECK_PASS' \
  'SEQ94_A39_DISPATCH_VERIFIED' \
  'archive_sha256=d427c9aca30e26b0f51f722c6ff67763e15e8be5398e744f54e6828193c223bb' \
  'slurm_sha256=fa0e3100bf1c069cf7006d0cf01740126d2d2253063dacb579cefdc433ac43df' \
  'preflight_sha256=5fd6712492b20e094826c9ec11b362f3595fd519f31cc85876d4d533bad93b77' \
  'source_root=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation4_20260831/source_A39_formal_evaluation_seq94'; do
  grep -Fq "${expected}" "${RESULT94}" || {
    echo "sequence-94 eval4 submission evidence differs at: ${expected}" >&2
    exit 43
  }
done
require_file "${RESULT96}" "${RESULT96_SHA256}" "${RESULT96_SIZE}" "sequence-96 eval4 terminal status"
grep -Fq '216974|daily-knet-a39-s94|sunyiq|hgpu8|FAILED|2:0|00:00:26|2026-08-31T16:22:54|2026-08-31T16:23:20|ngu202' "${RESULT96}" || {
  echo "sequence-96 eval4 terminal state differs" >&2
  exit 43
}
grep -Fq 'SEQ96_A39_STATUS_QUERY_COMPLETE job_id=216974 squeue_exit=1 sacct_exit=0' "${RESULT96}" || {
  echo "sequence-96 eval4 accounting completion differs" >&2
  exit 43
}
require_file "${RESULT97}" "${RESULT97_SHA256}" "${RESULT97_SIZE}" "sequence-97 eval4 terminal diagnostic"
for expected in \
  "A39_FORMAL_EVALUATION_TECHNICAL_ERROR: checkpoint identity hash differs: actual='5f1f3fa3a15a0430bc5ee90e51ecf976604a5a1b2d084a7e215c6387aa26a2c4' expected='1d4a5d9e8e1dc1be3d4382784db0125872addeb8d4ea789375b6413ebb524d0d'" \
  '"evaluation_array_payloads_materialized": 0' \
  'DIRECTORY_ABSENT path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation4_20260831/evaluation' \
  'DIRECTORY_ABSENT path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation4_20260831/verification' \
  'DIRECTORY_ABSENT path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation4_20260831/status/locks/DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL4_SEQ94.evaluation.lock' \
  'FILE_ABSENT label=result_summary' \
  'FILE_ABSENT label=access_ledger' \
  'FILE_ABSENT label=independent_verification' \
  'IDENTITY_ABSENT label=predictions' \
  'SEQ97_A39_TERMINAL_DIAGNOSTIC_COMPLETE job_id=216974'; do
  grep -Fq "${expected}" "${RESULT97}" || {
    echo "sequence-97 eval4 diagnostic differs at: ${expected}" >&2
    exit 43
  }
done
require_file "${RECONSTRUCTED_SOURCE}" "${RECONSTRUCTED_SHA256}" "${RECONSTRUCTED_SIZE}" "A38 reconstructed source archive"
require_file "${RECEIPT_SOURCE}" "${RECEIPT_SHA256}" "${RECEIPT_SIZE}" "A38 member-identity source receipt"
require_file "${ARCHIVE}" "${ARCHIVE_SHA256}" "${ARCHIVE_SIZE}" "A39 evaluation sealed archive"
require_file "${OUTER_MANIFEST}" "${OUTER_MANIFEST_SHA256}" "${OUTER_MANIFEST_SIZE}" "A39 evaluation outer manifest"
verify_outer_manifest

if [[ -e "${LOCK_ROOT}" || -L "${LOCK_ROOT}" ]]; then
  [[ -d "${LOCK_ROOT}" && ! -L "${LOCK_ROOT}" ]] || {
    echo "persistent submission lock is incomplete or unsafe" >&2
    exit 73
  }
  validate_prepared_owner
  recover_only
  exit 0
fi
[[ ! -e "${RUN_ROOT}" && ! -L "${RUN_ROOT}" ]] || {
  echo "new A39 evaluation root already exists without a recoverable lock" >&2
  exit 44
}

PRE_QUERY="$(mktemp -d /tmp/a39-seq98-pre.XXXXXX)"
query_scheduler "${PRE_QUERY}/pre"
mapfile -t PRE_IDS < <(matching_ids "${PRE_QUERY}/pre")
[[ "${#PRE_IDS[@]}" == 0 ]] || {
  echo "matching A39 evaluation job exists before preparation" >&2
  exit 74
}
mapfile -t PRE_ACTIVE_A39_IDS < <(active_a39_ids "${PRE_QUERY}/pre")
[[ "${#PRE_ACTIVE_A39_IDS[@]}" == 0 ]] || {
  echo "another A39 evaluation job is active before preparation" >&2
  exit 74
}

mkdir "${RUN_ROOT}"
mkdir -p "${SOURCE_ROOT}" "${EXTERNAL_EVIDENCE_ROOT}" "${STATUS_ROOT}/locks" "${RUN_ROOT}/logs"
cp "${PRE_QUERY}/pre.squeue" "${STATUS_ROOT}/prepared-pre-sbatch.squeue"
cp "${PRE_QUERY}/pre.sacct" "${STATUS_ROOT}/prepared-pre-sbatch.sacct"

python -B -S - "${ARCHIVE}" "${SOURCE_ROOT}" "${ARCHIVE_MEMBER_COUNT}" <<'PY'
import pathlib
import sys
import tarfile

archive = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
expected_count = int(sys.argv[3])
with tarfile.open(archive, "r:gz") as handle:
    members = handle.getmembers()
    if len(members) != expected_count:
        raise SystemExit("archive member count differs")
    names = set()
    for member in members:
        path = pathlib.PurePosixPath(member.name)
        if (
            path.is_absolute()
            or ".." in path.parts
            or path == pathlib.PurePosixPath(".")
            or not member.isfile()
            or member.name in names
        ):
            raise SystemExit(f"unsafe archive member: {member.name}")
        names.add(member.name)
    handle.extractall(target, filter="data")
PY
require_file "${SOURCE_ROOT}/bundle_manifest.json" "${INTERNAL_MANIFEST_SHA256}" "${INTERNAL_MANIFEST_SIZE}" "A39 internal manifest"
require_file "${SOURCE_ROOT}/${SLURM_REL}" "${SLURM_SHA256}" "${SLURM_SIZE}" "A39 Slurm entry"
require_file "${SOURCE_ROOT}/${PREFLIGHT_REL}" "${PREFLIGHT_SHA256}" "${PREFLIGHT_SIZE}" "A39 preflight entry"

RECONSTRUCTED_PENDING="${EXTERNAL_EVIDENCE_ROOT}/.reconstructed.pending"
RECEIPT_PENDING="${EXTERNAL_EVIDENCE_ROOT}/.receipt.pending"
for target in "${RECONSTRUCTED_RUNTIME}" "${RECEIPT_RUNTIME}" "${RECONSTRUCTED_PENDING}" "${RECEIPT_PENDING}"; do
  [[ ! -e "${target}" && ! -L "${target}" ]] || {
    echo "external-evidence destination already exists: ${target}" >&2
    exit 44
  }
done
cp --reflink=auto -- "${RECONSTRUCTED_SOURCE}" "${RECONSTRUCTED_PENDING}"
cp --reflink=auto -- "${RECEIPT_SOURCE}" "${RECEIPT_PENDING}"
require_file "${RECONSTRUCTED_PENDING}" "${RECONSTRUCTED_SHA256}" "${RECONSTRUCTED_SIZE}" "pending reconstructed evidence"
require_file "${RECEIPT_PENDING}" "${RECEIPT_SHA256}" "${RECEIPT_SIZE}" "pending member-identity receipt"
mv -T -- "${RECONSTRUCTED_PENDING}" "${RECONSTRUCTED_RUNTIME}"
mv -T -- "${RECEIPT_PENDING}" "${RECEIPT_RUNTIME}"
require_file "${RECONSTRUCTED_RUNTIME}" "${RECONSTRUCTED_SHA256}" "${RECONSTRUCTED_SIZE}" "runtime reconstructed evidence"
require_file "${RECEIPT_RUNTIME}" "${RECEIPT_SHA256}" "${RECEIPT_SIZE}" "runtime member-identity receipt"
(
  cd "${SOURCE_ROOT}"
  python -B -S - <<'PY'
from pathlib import Path

from hpc.daily_camels_knet_formal_evaluation.preflight import verify_bundle_root

verify_bundle_root(Path("."))
PY
)

query_scheduler "${STATUS_ROOT}/final-pre-sbatch"
mapfile -t FINAL_IDS < <(matching_ids "${STATUS_ROOT}/final-pre-sbatch")
[[ "${#FINAL_IDS[@]}" == 0 ]] || {
  echo "matching A39 evaluation job appeared during preparation" >&2
  exit 75
}
mapfile -t FINAL_ACTIVE_A39_IDS < <(active_a39_ids "${STATUS_ROOT}/final-pre-sbatch")
[[ "${#FINAL_ACTIVE_A39_IDS[@]}" == 0 ]] || {
  echo "another A39 evaluation job became active during preparation" >&2
  exit 75
}

mkdir "${LOCK_ROOT}"
OWNER_TEMPORARY="$(mktemp "${STATUS_ROOT}/owner.XXXXXX")"
python -B -S - \
  "${OWNER_TEMPORARY}" \
  "${EXPERIMENT_ID}" \
  "${EXECUTION_ID}" \
  "${SUBMISSION_TOKEN}" \
  "${ARCHIVE_SHA256}" \
  "${SLURM_SHA256}" \
  "$(sha256_file "${BASH_SOURCE[0]}")" \
  "${RESULT85_SHA256}" \
  "${RESULT88_SHA256}" \
  "${RESULT90_SHA256}" \
  "${RESULT91_SHA256}" \
  "${RESULT92_SHA256}" \
  "${RESULT93_SHA256}" \
  "${RESULT94_SHA256}" \
  "${RESULT96_SHA256}" \
  "${RESULT97_SHA256}" \
  "${RECONSTRUCTED_SHA256}" \
  "${RECEIPT_SHA256}" <<'PY'
import datetime
import json
import os
import pathlib
import socket
import sys

path = pathlib.Path(sys.argv[1])
(
    experiment_id,
    execution_id,
    token,
    archive_sha,
    slurm_sha,
    controller_sha,
    result85_sha,
    result88_sha,
    result90_sha,
    result91_sha,
    result92_sha,
    result93_sha,
    result94_sha,
    result96_sha,
    result97_sha,
    reconstructed_sha,
    receipt_sha,
) = sys.argv[2:]
payload = {
    "created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "experiment_id": experiment_id,
    "execution_id": execution_id,
    "submission_token": token,
    "state": "PREPARED",
    "persistent": True,
    "evaluation_only": True,
    "archive_sha256": archive_sha,
    "slurm_sha256": slurm_sha,
    "controller_sha256": controller_sha,
    "eval1_diagnostic_result85_sha256": result85_sha,
    "eval2_diagnostic_result88_sha256": result88_sha,
    "member_identity_result90_sha256": result90_sha,
    "eval3_submission_result91_sha256": result91_sha,
    "eval3_terminal_result92_sha256": result92_sha,
    "eval3_diagnostic_result93_sha256": result93_sha,
    "eval4_submission_result94_sha256": result94_sha,
    "eval4_terminal_result96_sha256": result96_sha,
    "eval4_diagnostic_result97_sha256": result97_sha,
    "prior_failed_job_id": "216974",
    "prior_failure_class": "recoverable_checkpoint_identity_canonicalization_mismatch",
    "reconstructed_terminal_evidence_sha256": reconstructed_sha,
    "member_identity_receipt_sha256": receipt_sha,
    "transport_repair_reason": "original container missing; all 33 reconstructed members independently matched original inventory",
    "eval3_repair_reason": "fixed one-GPU request and runtime visibility proofs remain strict; unreliable optional Slurm GPU-count field is recorded but no longer mandatory",
    "eval4_repair_reason": "checkpoint identity validation now uses the trainer's compact canonical JSON bytes while formal output formatting remains unchanged",
    "owner_user": "sunyiq",
    "owner_host": socket.gethostname(),
    "owner_pid": os.getpid(),
    "mailbox_sequence": 98,
}
with path.open("w", encoding="utf-8") as handle:
    json.dump(payload, handle, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
ln "${OWNER_TEMPORARY}" "${OWNER_JSON}"
rm "${OWNER_TEMPORARY}"
validate_prepared_owner

SBATCH_STDOUT="${STATUS_ROOT}/sbatch.stdout"
SBATCH_STDERR="${STATUS_ROOT}/sbatch.stderr"
SBATCH_EXIT_FILE="${STATUS_ROOT}/sbatch.exit"
set +e
(
  cd "${SOURCE_ROOT}" || exit 97
  sbatch --parsable \
    --chdir="${SOURCE_ROOT}" \
    --job-name="${JOB_NAME}" \
    --comment="${SUBMISSION_COMMENT}" \
    --export="ALL,A39_SUBMISSION_TOKEN=${SUBMISSION_TOKEN},A39_BUNDLE_ROOT=${SOURCE_ROOT},A39_A38_TERMINAL_EVIDENCE=${RECONSTRUCTED_RUNTIME},A39_A38_RECONSTRUCTION_RECEIPT=${RECEIPT_RUNTIME}" \
    "${SOURCE_ROOT}/${SLURM_REL}"
) > "${SBATCH_STDOUT}" 2> "${SBATCH_STDERR}"
SBATCH_EXIT=$?
set -e
printf '%s\n' "${SBATCH_EXIT}" > "${SBATCH_EXIT_FILE}"
RAW_RECEIPT="$(tr -d '\r\n' < "${SBATCH_STDOUT}")"
JOB_ID="${RAW_RECEIPT%%;*}"
if [[ "${SBATCH_EXIT}" == 0 && "${RAW_RECEIPT}" =~ ^[0-9]+(\;[^[:space:]]+)?$ && "${JOB_ID}" =~ ^[0-9]+$ ]]; then
  record_job_id "${JOB_ID}"
  query_scheduler "${STATUS_ROOT}/post-sbatch"
  mapfile -t POST_IDS < <(matching_ids "${STATUS_ROOT}/post-sbatch")
  if [[ "${#POST_IDS[@]}" != 1 || "${POST_IDS[0]}" != "${JOB_ID}" ]]; then
    echo "job ${JOB_ID} was submitted and recorded, but post-submit uniqueness proof differs; do not resubmit" >&2
    exit 76
  fi
  echo "SEQ98_A39_FORMAL_EVALUATION_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_id=${EXECUTION_ID} job_id=${JOB_ID} archive_sha256=${ARCHIVE_SHA256} manifest_sha256=${OUTER_MANIFEST_SHA256} slurm_sha256=${SLURM_SHA256} preflight_sha256=${PREFLIGHT_SHA256} result85_sha256=${RESULT85_SHA256} result88_sha256=${RESULT88_SHA256} result90_sha256=${RESULT90_SHA256} result91_sha256=${RESULT91_SHA256} result92_sha256=${RESULT92_SHA256} result93_sha256=${RESULT93_SHA256} result94_sha256=${RESULT94_SHA256} result96_sha256=${RESULT96_SHA256} result97_sha256=${RESULT97_SHA256} reconstructed_sha256=${RECONSTRUCTED_SHA256} receipt_sha256=${RECEIPT_SHA256} root=${RUN_ROOT} source_root=${SOURCE_ROOT}"
  exit 0
fi
echo "sbatch receipt is ambiguous (exit=${SBATCH_EXIT}); entering query-only recovery with no sbatch retry" >&2
recover_only
