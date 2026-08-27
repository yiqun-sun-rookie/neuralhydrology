#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/parity-a37-resume-probe2-v35"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_PROBE2_SEQ35"
ARCHIVE="${PAYLOAD_DIRECTORY}/${EXPERIMENT_ID}.tar.gz"
OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/A37_bundle_manifest.sha256.json"
ARCHIVE_SHA256="feb7ee1f1257f021991f6d380cb49b5171af42d4de54811428f2944c1da22e81"
ARCHIVE_SIZE=1815377
OUTER_MANIFEST_SHA256="78a3a2cc642e91af2397afc542a7eff45dcf3cee17bb467fdb20ab595507859d"
OUTER_MANIFEST_SIZE=11419
INTERNAL_MANIFEST_SHA256="b0d374d72d5105735c9455271ec0f778831fa7ad2ec64c7ef4841299651cb13e"
CONFIG_SHA256="70a522e9306c80d6c3010a3fbcf7fda3b4f53d850498698e1ef15f1028441984"
PROBE_SCRIPT_SHA256="4094e0c1480481c352d4e42cf5ae4e732e18323dd772f063033e2c25e2f2ede0"
CHECKPOINT_SHA256="b2b93f531c7ad4922e14d5479564e82e5a6dca553835bbc8cc8af61db4a8d81e"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_resume1_20260826"
SOURCE_DIRECTORY="${RUN_BASE}/source_A37_probe2_seq35"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
PREVIOUS_PROBE_JOB_ID="213858"
PREVIOUS_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_34.txt"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_regular_identity() {
  local path="$1" expected_sha256="$2" expected_size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "${label} is absent, non-regular, or symbolic: ${path}" >&2
    return 50
  }
  [[ "$(stat -c '%s' "$path")" = "$expected_size" ]] || {
    echo "${label} size differs" >&2
    return 51
  }
  [[ "$(sha256_file "$path")" = "$expected_sha256" ]] || {
    echo "${label} SHA-256 differs" >&2
    return 52
  }
}

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  echo "fixed-user check failed" >&2
  exit 53
fi

require_regular_identity "$ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "A37 repaired archive"
require_regular_identity "$OUTER_MANIFEST" "$OUTER_MANIFEST_SHA256" "$OUTER_MANIFEST_SIZE" "A37 repaired outer manifest"
[[ -f "$PREVIOUS_RESULT" && ! -L "$PREVIOUS_RESULT" ]] || {
  echo "sequence 34 terminal receipt is absent or symbolic" >&2
  exit 54
}
grep -Fq 'SEQ34_A37_PROBE_TERMINAL state=FAILED exit_code=1:0 job_id=213858' "$PREVIOUS_RESULT" || {
  echo "sequence 34 does not prove the previous probe terminal identity" >&2
  exit 55
}
grep -Fq 'ValueError: continuation requires an explicit --resume checkpoint' "$PREVIOUS_RESULT" || {
  echo "sequence 34 does not prove the repaired integration failure" >&2
  exit 56
}
PREVIOUS_STATE="$(sacct -n -X -j "$PREVIOUS_PROBE_JOB_ID" --format=State -P 2>/dev/null | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
[[ "$PREVIOUS_STATE" = "FAILED" ]] || {
  echo "previous probe 213858 is not in the expected FAILED terminal state: ${PREVIOUS_STATE:-UNKNOWN}" >&2
  exit 57
}

for path in "$RUN_BASE" "$STATUS_DIRECTORY" "$LOG_DIRECTORY" "${RUN_BASE}/runs"; do
  [[ -d "$path" && ! -L "$path" ]] || {
    echo "existing isolated A37 directory is absent, non-directory, or symbolic: $path" >&2
    exit 58
  }
done
for path in "$SOURCE_DIRECTORY" "$RUN_DIRECTORY" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.probe.lock" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "A37 source, output, or owner lock already exists: $path" >&2
    exit 59
  }
done

SQUEUE_SNAPSHOT="$(mktemp)"
trap 'rm -f "$SQUEUE_SNAPSHOT"' EXIT
if ! squeue -h -u "$EXPECTED_USER" -o '%A|%j|%T|%Z|%o' > "$SQUEUE_SNAPSHOT"; then
  echo "unable to prove A37 active-job uniqueness" >&2
  exit 60
fi
if awk -F'|' -v experiment="$EXPERIMENT_ID" -v run_base="$RUN_BASE" '
  $2 == "daily-knet-a37-probe" || $2 == "daily-knet-a37" ||
  index($0, experiment) || index($0, run_base) { found=1 }
  END { exit(found ? 0 : 1) }
' "$SQUEUE_SNAPSHOT"; then
  echo "an A37 probe or training job already exists; refusing duplicate submission" >&2
  exit 61
fi

python - "$ARCHIVE" "$OUTER_MANIFEST" "$EXPERIMENT_ID" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "$INTERNAL_MANIFEST_SHA256" "$CONFIG_SHA256" "$PROBE_SCRIPT_SHA256" "$CHECKPOINT_SHA256" <<'PY'
from hashlib import sha256
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

archive = Path(sys.argv[1])
outer_path = Path(sys.argv[2])
experiment_id = sys.argv[3]
archive_sha = sys.argv[4]
archive_size = int(sys.argv[5])
internal_sha = sys.argv[6]
config_sha = sys.argv[7]
probe_script_sha = sys.argv[8]
checkpoint_sha = sys.argv[9]

outer = json.loads(outer_path.read_text(encoding="utf-8"))
continuation = outer.get("continuation", {})
active_config = "configs/daily_camels_knet_fixed_full_training_coverage_epoch10_to40_resume_a37.json"
probe_script = "hpc/daily_camels_ukf_knet_parity/submit_probe_gpu.slurm"
checkpoint = (
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/"
    "ff2084c4/seq15_snapshot_2831/run/checkpoints/epoch_010.pt"
)
if (
    outer.get("schema_version") != "daily_camels_ukf_knet_parity_hpc_archive_v1"
    or outer.get("experiment_id") != experiment_id
    or outer.get("archive_sha256") != archive_sha
    or int(outer.get("archive_size", -1)) != archive_size
    or int(outer.get("member_count", -1)) != 46
    or int(outer.get("reserved_data_member_count", -1)) != 0
    or int(outer.get("resume_checkpoint_count", -1)) != 1
    or int(outer.get("array_members_materialized_during_build", -1)) != 0
    or outer.get("internal_manifest_sha256") != internal_sha
    or outer.get("active_config_member") != active_config
    or outer.get("member_sha256", {}).get(active_config) != config_sha
    or outer.get("member_sha256", {}).get(probe_script) != probe_script_sha
    or outer.get("member_sha256", {}).get(checkpoint) != checkpoint_sha
    or continuation.get("checkpoint_path") != checkpoint
    or continuation.get("checkpoint_sha256") != checkpoint_sha
    or int(continuation.get("completed_epoch", -1)) != 10
    or int(continuation.get("optimizer_steps", -1)) != 10
    or int(continuation.get("sampled_forecast_events", -1)) != 76500
):
    raise SystemExit("A37 repaired outer manifest or continuation identity differs")

with tarfile.open(archive, "r:gz") as handle:
    members = handle.getmembers()
    if len(members) != 47:
        raise SystemExit("A37 repaired archive member count including internal manifest differs")
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or not member.isfile():
            raise SystemExit(f"unsafe or non-regular A37 archive member: {member.name}")
    stream = handle.extractfile("bundle_manifest.json")
    if stream is None:
        raise SystemExit("A37 internal manifest cannot be read")
    internal_bytes = stream.read()
if sha256(internal_bytes).hexdigest() != internal_sha:
    raise SystemExit("A37 repaired internal manifest SHA-256 differs")
internal = json.loads(internal_bytes.decode("utf-8"))
if (
    internal.get("experiment_id") != experiment_id
    or int(internal.get("member_count", -1)) != 46
    or int(internal.get("reserved_data_member_count", -1)) != 0
    or int(internal.get("resume_checkpoint_count", -1)) != 1
    or internal.get("member_sha256") != outer.get("member_sha256")
):
    raise SystemExit("A37 repaired internal and outer manifests disagree")
PY

mkdir "$SOURCE_DIRECTORY"
{
  printf 'experiment_id=%s\n' "$EXPERIMENT_ID"
  printf 'execution_attempt_id=%s\n' "$EXECUTION_ATTEMPT_ID"
  printf 'archive=%s\n' "$ARCHIVE"
  printf 'archive_sha256=%s\n' "$ARCHIVE_SHA256"
  printf 'archive_size=%s\n' "$ARCHIVE_SIZE"
  printf 'outer_manifest=%s\n' "$OUTER_MANIFEST"
  printf 'outer_manifest_sha256=%s\n' "$OUTER_MANIFEST_SHA256"
  printf 'previous_probe_job_id=%s\n' "$PREVIOUS_PROBE_JOB_ID"
  printf 'previous_probe_terminal_state=%s\n' "$PREVIOUS_STATE"
} > "${STATUS_DIRECTORY}/seq35_submission_identity.txt"
cp "$SQUEUE_SNAPSHOT" "${STATUS_DIRECTORY}/seq35_pre_submission_squeue.txt"
tar -xzf "$ARCHIVE" -C "$SOURCE_DIRECTORY"

set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${SOURCE_DIRECTORY}/src:${SOURCE_DIRECTORY}"
cd "$SOURCE_DIRECTORY"
python -u hpc/daily_camels_ukf_knet_parity/preflight.py \
  --bundle-root "$SOURCE_DIRECTORY" \
  --phase train \
  --offline-bundle-check \
  --report "${STATUS_DIRECTORY}/seq35_offline_A37.json"

for path in "$RUN_DIRECTORY" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.probe.lock" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "A37 output or owner lock appeared before repaired probe submission: $path" >&2
    exit 62
  }
done
if ! squeue -h -u "$EXPECTED_USER" -o '%A|%j|%T|%Z|%o' > "$SQUEUE_SNAPSHOT"; then
  echo "unable to refresh A37 active-job uniqueness immediately before submission" >&2
  exit 63
fi
cp "$SQUEUE_SNAPSHOT" "${STATUS_DIRECTORY}/seq35_immediate_pre_submission_squeue.txt"
if awk -F'|' -v experiment="$EXPERIMENT_ID" -v run_base="$RUN_BASE" '
    $2 == "daily-knet-a37-probe" || $2 == "daily-knet-a37" ||
    index($0, experiment) || index($0, run_base) { found=1 }
    END { exit(found ? 0 : 1) }
' "$SQUEUE_SNAPSHOT"; then
  echo "an A37 job appeared during repaired preflight; refusing duplicate submission" >&2
  exit 64
fi

SUBMISSION_RAW="$(sbatch --parsable --mem=0 \
  -J daily-knet-a37-probe \
  -o "${LOG_DIRECTORY}/probe-%j.out" \
  -e "${LOG_DIRECTORY}/probe-%j.err" \
  --export="ALL,PARITY_REMOTE_ROOT=${RUN_BASE}" \
  hpc/daily_camels_ukf_knet_parity/submit_probe_gpu.slurm)"
PROBE_JOB_ID="${SUBMISSION_RAW%%;*}"
case "$PROBE_JOB_ID" in
  ''|*[!0-9]*)
    echo "invalid repaired A37 probe Slurm job identifier: ${SUBMISSION_RAW}" >&2
    exit 65
    ;;
esac
printf '%s\n' "$PROBE_JOB_ID" > "${STATUS_DIRECTORY}/seq35_probe_job_id.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "${STATUS_DIRECTORY}/seq35_probe_submitted_time_utc.txt"
if ! squeue -h -j "$PROBE_JOB_ID" -o '%A|%j|%T|%R|%Z|%o' > "${STATUS_DIRECTORY}/seq35_post_submission_squeue.txt" 2>&1; then
  printf 'post_submission_squeue_unavailable_or_job_already_terminal=1\n' >> "${STATUS_DIRECTORY}/seq35_post_submission_squeue.txt"
fi
printf 'SEQ35_A37_RESOURCE_PROBE2_SUBMITTED experiment_id=%s execution_attempt_id=%s job_id=%s run_base=%s archive_sha256=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$PROBE_JOB_ID" "$RUN_BASE" "$ARCHIVE_SHA256"
