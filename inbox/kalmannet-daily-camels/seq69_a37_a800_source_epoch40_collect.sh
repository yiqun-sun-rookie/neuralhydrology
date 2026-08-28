#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT68="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_68.txt"
RESULT68_SHA256="72bdeafa849cac9910fa89d11ab8927d1d4b8786c165c0befa7175c16092ac79"
RESULT68_SIZE="14202549"
JOB_ID="215699"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_TRAIN4_SEQ65"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_train4_20260827"
SOURCE_REL="source_A37_a800_train4_seq65"
RUN_REL="runs/${EXPERIMENT_ID}"
SOURCE_DIRECTORY="${RUN_BASE}/${SOURCE_REL}"
RUN_DIRECTORY="${RUN_BASE}/${RUN_REL}"
CHECKPOINT_REL="${RUN_REL}/checkpoints/epoch_040.pt"
CHECKPOINT="${RUN_BASE}/${CHECKPOINT_REL}"
ARCHIVE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A37_FINAL_SOURCE_EPOCH40_SEQ69.tar.gz"
PARTIAL_ARCHIVE="${ARCHIVE}.partial.$$"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_regular_identity() {
  local path="$1" expected_sha256="$2" expected_size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "${label} is absent, non-regular, or symbolic: ${path}" >&2
    return 50
  }
  [[ "$(stat -c '%s' "$path")" == "$expected_size" ]] || {
    echo "${label} size differs" >&2
    return 51
  }
  [[ "$(sha256_file "$path")" == "$expected_sha256" ]] || {
    echo "${label} SHA-256 differs" >&2
    return 52
  }
}

reserved_named_path() {
  shopt -s nocasematch
  if [[ "$1" =~ held.?out|reserved.?evaluation|formal.?evaluation ]]; then
    shopt -u nocasematch
    return 0
  fi
  shopt -u nocasematch
  return 1
}

cleanup_partial() {
  if [[ -f "$PARTIAL_ARCHIVE" && ! -L "$PARTIAL_ARCHIVE" ]]; then
    rm -f -- "$PARTIAL_ARCHIVE"
  fi
}
trap cleanup_partial EXIT

[[ "${USER-}" == "$EXPECTED_USER" && "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 53
}

require_regular_identity "$RESULT68" "$RESULT68_SHA256" "$RESULT68_SIZE" "sequence 68 terminal receipt"
grep -Fxq "SEQ68_A37_A800_TERMINAL_COLLECTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} job_id=${JOB_ID} terminal_state=FAILED terminal_exit_code=2:0 partition=hgpu8 node=ngu202 reserved_named_path_count=0 run_directory_present=1 completion_marker_present=1 failure_file_present=0 training_lock_present=0 run_owner_lock_present=0" "$RESULT68" || {
  echo "sequence 68 terminal identity differs" >&2
  exit 54
}
grep -Fxq '### exit_code=0' "$RESULT68" || {
  echo "sequence 68 mailbox command did not complete successfully" >&2
  exit 55
}

ACCOUNTING_LINE="$(
  sacct -n -X -j "$JOB_ID" --parsable2 --format=State,ExitCode,JobName,User,Partition,NodeList |
    awk 'NF {print; exit}'
)"
[[ -n "$ACCOUNTING_LINE" ]] || {
  echo "formal training accounting is empty" >&2
  exit 56
}
IFS='|' read -r STATE EXIT_CODE JOB_NAME ACCOUNTING_USER PARTITION NODELIST _ <<<"$ACCOUNTING_LINE"
STATE="$(printf '%s' "$STATE" | sed 's/[+ ].*$//')"
[[ "$STATE" == "FAILED" && "$EXIT_CODE" == "2:0" && "$JOB_NAME" == "daily-knet-a37" ]] || {
  echo "formal training terminal identity changed" >&2
  exit 57
}
[[ "$ACCOUNTING_USER" == "$EXPECTED_USER" && "$PARTITION" == "hgpu8" && "$NODELIST" == "ngu202" ]] || {
  echo "formal training accounting identity differs" >&2
  exit 58
}

for directory in "$RUN_BASE" "$SOURCE_DIRECTORY" "$RUN_DIRECTORY" "${RUN_DIRECTORY}/checkpoints"; do
  [[ -d "$directory" && ! -L "$directory" ]] || {
    echo "required directory is absent or symbolic: $directory" >&2
    exit 59
  }
done

if find -P "$SOURCE_DIRECTORY" -type l -print -quit | grep -q .; then
  echo "symbolic link found in exact source snapshot" >&2
  exit 60
fi

RESERVED_NAMED_PATH_COUNT=0
while IFS= read -r -d '' path; do
  if reserved_named_path "$path"; then
    printf 'reserved-named path rejected: %s\n' "$path" >&2
    RESERVED_NAMED_PATH_COUNT=$((RESERVED_NAMED_PATH_COUNT + 1))
  fi
done < <(find -P "$SOURCE_DIRECTORY" -print0)
[[ "$RESERVED_NAMED_PATH_COUNT" == "0" ]] || exit 61

require_regular_identity \
  "${SOURCE_DIRECTORY}/bundle_manifest.json" \
  "f504579439c5f9b0b22b399b23bf876d60f879002fb1e06e2f23312b85b7ead7" \
  "18323" \
  "A37 exact source bundle manifest"
require_regular_identity \
  "${SOURCE_DIRECTORY}/configs/daily_camels_knet_fixed_full_training_coverage_epoch10_to40_resume_a37.json" \
  "29b4bdb604f2bfbba5c1ab78576a7a21811cd0fdd75060b2dc328ff608f06f2a" \
  "10215" \
  "A37 exact source config"
require_regular_identity \
  "${SOURCE_DIRECTORY}/scripts/run_daily_camels_ukf_knet_parity.py" \
  "b5c7c1ec0d38d6c9721af786351bb57995b9ec66fcf022ea5e36dbae173df434" \
  "210729" \
  "A37 exact source runner"
require_regular_identity \
  "$CHECKPOINT" \
  "43ed17aaacabdae7e88a80de8567ac3d29d88635d93f701016c757e7f3a407f5" \
  "3174920" \
  "A37 epoch-40 atomic checkpoint"
require_regular_identity \
  "${RUN_DIRECTORY}/result_summary.json" \
  "e0393fde7084575f89f17e9f64945aafe064c72e3e60f36892376a8965cbb153" \
  "3665887" \
  "A37 result summary"
require_regular_identity \
  "${RUN_DIRECTORY}/epoch_history.json" \
  "ec64cd575dc76312ef9beaafa22c19fd0d82dec552405ac9c04923aeae2af636" \
  "3754380" \
  "A37 epoch history"
require_regular_identity \
  "${RUN_DIRECTORY}/completion.marker.json" \
  "2b40523a6667ee8794d0c4e705d65711ea1b3d95311b0c3f870ca20d25263c76" \
  "523" \
  "A37 completion marker"
require_regular_identity \
  "${RUN_DIRECTORY}/experiment_identity.json" \
  "6015e3473a478d96908ab9eda46e582244968480db592e056ebc51d3842c1e7a" \
  "3250" \
  "A37 experiment identity"

SAFE_RUN_FILES=(
  "$CHECKPOINT_REL"
  "${RUN_REL}/result_summary.json"
  "${RUN_REL}/epoch_history.json"
  "${RUN_REL}/completion.marker.json"
  "${RUN_REL}/experiment_identity.json"
  "${RUN_REL}/replay_evidence.json"
  "${RUN_REL}/manifest.sha256.json"
)
for relative_path in "${SAFE_RUN_FILES[@]}"; do
  if reserved_named_path "$relative_path"; then
    echo "safe run file unexpectedly has a reserved name: $relative_path" >&2
    exit 62
  fi
  [[ -f "${RUN_BASE}/${relative_path}" && ! -L "${RUN_BASE}/${relative_path}" ]] || {
    echo "safe run evidence is absent, non-regular, or symbolic: $relative_path" >&2
    exit 63
  }
done

[[ ! -e "$ARCHIVE" && ! -L "$ARCHIVE" ]] || {
  echo "non-overwrite archive target already exists: $ARCHIVE" >&2
  exit 64
}
[[ ! -e "$PARTIAL_ARCHIVE" && ! -L "$PARTIAL_ARCHIVE" ]] || {
  echo "partial archive target already exists: $PARTIAL_ARCHIVE" >&2
  exit 65
}

tar -C "$RUN_BASE" -czf "$PARTIAL_ARCHIVE" -- "$SOURCE_REL" "${SAFE_RUN_FILES[@]}"
chmod 600 "$PARTIAL_ARCHIVE"
mv -n -- "$PARTIAL_ARCHIVE" "$ARCHIVE"
[[ -f "$ARCHIVE" && ! -L "$ARCHIVE" && ! -e "$PARTIAL_ARCHIVE" ]] || {
  echo "atomic non-overwrite archive promotion failed" >&2
  exit 66
}
trap - EXIT

ARCHIVE_SHA256="$(sha256_file "$ARCHIVE")"
ARCHIVE_SIZE="$(stat -c '%s' "$ARCHIVE")"
ARCHIVE_MEMBER_COUNT="$(tar -tzf "$ARCHIVE" | wc -l | tr -d ' ')"
ARCHIVE_EPOCH40_COUNT="$(tar -tzf "$ARCHIVE" | grep -Fxc "$CHECKPOINT_REL")"
ARCHIVE_RESERVED_COUNT="$(tar -tzf "$ARCHIVE" | grep -Eic 'held.?out|reserved.?evaluation|formal.?evaluation' || true)"
[[ "$ARCHIVE_EPOCH40_COUNT" == "1" && "$ARCHIVE_RESERVED_COUNT" == "0" ]] || {
  echo "archive member safety check failed" >&2
  exit 67
}

printf 'SEQ69_A37_SOURCE_EPOCH40_ARCHIVE experiment_id=%s execution_attempt_id=%s job_id=%s terminal_state=%s terminal_exit_code=%s archive=%s archive_sha256=%s archive_size=%s archive_member_count=%s epoch40_member_count=%s reserved_named_member_count=%s reserved_evaluation_access_count=0\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$STATE" "$EXIT_CODE" "$ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "$ARCHIVE_MEMBER_COUNT" "$ARCHIVE_EPOCH40_COUNT" "$ARCHIVE_RESERVED_COUNT"
printf '%s\n' 'SEQ69_A37_SOURCE_EPOCH40_MEMBERS_BEGIN'
tar -tzf "$ARCHIVE"
printf '%s\n' 'SEQ69_A37_SOURCE_EPOCH40_MEMBERS_END'
printf '%s\n' 'SEQ69_A37_SOURCE_EPOCH40_BASE64_BEGIN'
base64 -w 76 "$ARCHIVE"
printf '%s\n' 'SEQ69_A37_SOURCE_EPOCH40_BASE64_END'
printf 'SEQ69_A37_SOURCE_EPOCH40_COLLECTED source_manifest_sha256=%s source_config_sha256=%s source_runner_sha256=%s epoch40_checkpoint_sha256=%s result_summary_sha256=%s epoch_history_sha256=%s completion_marker_sha256=%s experiment_identity_sha256=%s\n' \
  "f504579439c5f9b0b22b399b23bf876d60f879002fb1e06e2f23312b85b7ead7" \
  "29b4bdb604f2bfbba5c1ab78576a7a21811cd0fdd75060b2dc328ff608f06f2a" \
  "b5c7c1ec0d38d6c9721af786351bb57995b9ec66fcf022ea5e36dbae173df434" \
  "43ed17aaacabdae7e88a80de8567ac3d29d88635d93f701016c757e7f3a407f5" \
  "e0393fde7084575f89f17e9f64945aafe064c72e3e60f36892376a8965cbb153" \
  "ec64cd575dc76312ef9beaafa22c19fd0d82dec552405ac9c04923aeae2af636" \
  "2b40523a6667ee8794d0c4e705d65711ea1b3d95311b0c3f870ca20d25263c76" \
  "6015e3473a478d96908ab9eda46e582244968480db592e056ebc51d3842c1e7a"
