#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
OUTBOX_ROOT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"
SOURCE_COLLECTOR="${CHANNEL_ROOT}/seq82_a38_a800_job215801_terminal_recollect.sh"
RESULT82="${OUTBOX_ROOT}/result_82.txt"
RESULT88="${OUTBOX_ROOT}/result_88.txt"
ORIGINAL_ARCHIVE="${OUTBOX_ROOT}/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ82.tar.gz"
RECONSTRUCTION_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_terminal_evidence_reconstruct_seq89_20260831"
RECONSTRUCTED_ARCHIVE="${RECONSTRUCTION_ROOT}/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_RECONSTRUCT_SEQ89.tar.gz"
PATCHED_COLLECTOR="${RECONSTRUCTION_ROOT}/seq89_patched_seq82_collector.sh"
RECONSTRUCTION_RECEIPT="${RECONSTRUCTION_ROOT}/reconstruction_receipt.txt"

SOURCE_COLLECTOR_SHA256="511e1f427fe951dc8ada3f7b05d73178af1407ed052ae60129089d5f413fc206"
SOURCE_COLLECTOR_SIZE="81514"
RESULT82_SHA256="a16bfb72c526ff8ec15bb5940b80d4abe8aabe96ffda6bdd322ea604a4229e69"
RESULT82_SIZE="7403339"
RESULT88_SHA256="3d275a97832907159085ee83a20b2649cf9e0a8e69ccfbe4684a288dca748bfb"
RESULT88_SIZE="6736"
ORIGINAL_ARCHIVE_SHA256="72feda409ea3490ccd9a289b1313c9beb276c1cc267a15111dc19e63d5815317"
ORIGINAL_ARCHIVE_SIZE="13900887"
ORIGINAL_ARCHIVE_LINE='ARCHIVE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ82.tar.gz"'

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

[[ "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "sequence 89 must run as ${EXPECTED_USER}" >&2
  exit 53
}
[[ -d "/data1/home/sunyiq" && ! -L "/data1/home/sunyiq" ]] || {
  echo "stable home root is absent or symbolic" >&2
  exit 53
}
require_regular_identity "$SOURCE_COLLECTOR" "$SOURCE_COLLECTOR_SHA256" "$SOURCE_COLLECTOR_SIZE" "original sequence 82 collector"
require_regular_identity "$RESULT82" "$RESULT82_SHA256" "$RESULT82_SIZE" "sequence 82 terminal receipt"
require_regular_identity "$RESULT88" "$RESULT88_SHA256" "$RESULT88_SIZE" "sequence 88 A39 failure receipt"

grep -Fq "SEQ82_A38_TERMINAL_COLLECTED " "$RESULT82" || {
  echo "sequence 82 terminal collection marker is absent" >&2
  exit 54
}
grep -Fq "archive_sha256=${ORIGINAL_ARCHIVE_SHA256} archive_size=${ORIGINAL_ARCHIVE_SIZE} archive_member_count=33 archive_reserved_member_count=0" "$RESULT82" || {
  echo "sequence 82 original archive identity differs" >&2
  exit 54
}
grep -Fxq '### exit_code=0' "$RESULT82" || {
  echo "sequence 82 did not complete successfully" >&2
  exit 54
}
grep -Fq "external A39 artifact is absent, non-regular, or symbolic: ${ORIGINAL_ARCHIVE}" "$RESULT88" || {
  echo "sequence 88 failure is not the registered missing-evidence condition" >&2
  exit 55
}
grep -Fxq 'DIRECTORY_ABSENT path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation2_20260831/evaluation' "$RESULT88" || {
  echo "sequence 88 does not prove that evaluation output remained absent" >&2
  exit 55
}
grep -Fxq 'DIRECTORY_ABSENT path=/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation2_20260831/verification' "$RESULT88" || {
  echo "sequence 88 does not prove that independent verification remained absent" >&2
  exit 55
}
grep -Fxq '### exit_code=0' "$RESULT88" || {
  echo "sequence 88 diagnostic did not complete successfully" >&2
  exit 55
}
[[ ! -e "$ORIGINAL_ARCHIVE" && ! -L "$ORIGINAL_ARCHIVE" ]] || {
  echo "original sequence 82 archive unexpectedly exists; reconstruction is refused" >&2
  exit 56
}
[[ ! -e "$RECONSTRUCTION_ROOT" && ! -L "$RECONSTRUCTION_ROOT" ]] || {
  echo "sequence 89 reconstruction root already exists" >&2
  exit 57
}

mkdir -m 700 -- "$RECONSTRUCTION_ROOT"
[[ -d "$RECONSTRUCTION_ROOT" && ! -L "$RECONSTRUCTION_ROOT" ]] || {
  echo "sequence 89 reconstruction root was not created safely" >&2
  exit 57
}

SOURCE_ARCHIVE_LINE_COUNT="$(grep -Fxc "$ORIGINAL_ARCHIVE_LINE" "$SOURCE_COLLECTOR")"
[[ "$SOURCE_ARCHIVE_LINE_COUNT" == "1" ]] || {
  echo "original collector archive assignment is not unique" >&2
  exit 58
}
sed "s#^ARCHIVE=.*#ARCHIVE=\"${RECONSTRUCTED_ARCHIVE}\"#" "$SOURCE_COLLECTOR" > "$PATCHED_COLLECTOR"
chmod 700 -- "$PATCHED_COLLECTOR"
[[ "$(grep -Fxc "ARCHIVE=\"${RECONSTRUCTED_ARCHIVE}\"" "$PATCHED_COLLECTOR")" == "1" ]] || {
  echo "patched collector archive assignment differs" >&2
  exit 58
}
if grep -Fq "$ORIGINAL_ARCHIVE_LINE" "$PATCHED_COLLECTOR"; then
  echo "patched collector still targets the ephemeral mailbox archive" >&2
  exit 58
fi

PATCHED_COLLECTOR_SHA256="$(sha256_file "$PATCHED_COLLECTOR")"
PATCHED_COLLECTOR_SIZE="$(stat -c '%s' "$PATCHED_COLLECTOR")"
printf 'SEQ89_A38_EVIDENCE_RECONSTRUCTION_BEGIN source_collector_sha256=%s source_collector_size=%s patched_collector_sha256=%s patched_collector_size=%s original_archive_absent=true evaluation_array_reads=0\n' \
  "$SOURCE_COLLECTOR_SHA256" "$SOURCE_COLLECTOR_SIZE" "$PATCHED_COLLECTOR_SHA256" "$PATCHED_COLLECTOR_SIZE"

bash "$PATCHED_COLLECTOR"

[[ -f "$RECONSTRUCTED_ARCHIVE" && ! -L "$RECONSTRUCTED_ARCHIVE" ]] || {
  echo "reconstructed A38 terminal archive is absent or unsafe" >&2
  exit 59
}
gzip -t "$RECONSTRUCTED_ARCHIVE"
RECONSTRUCTED_SHA256="$(sha256_file "$RECONSTRUCTED_ARCHIVE")"
RECONSTRUCTED_SIZE="$(stat -c '%s' "$RECONSTRUCTED_ARCHIVE")"
RECONSTRUCTED_MEMBER_COUNT="$(tar -tzf "$RECONSTRUCTED_ARCHIVE" | sed '/^$/d' | wc -l | tr -d ' ')"
RECONSTRUCTED_RESERVED_MEMBER_COUNT="$(tar -tzf "$RECONSTRUCTED_ARCHIVE" | awk 'BEGIN{IGNORECASE=1} /held.?out|reserved.?evaluation|formal.?evaluation/{count++} END{print count+0}')"
[[ "$RECONSTRUCTED_MEMBER_COUNT" == "33" && "$RECONSTRUCTED_RESERVED_MEMBER_COUNT" == "0" ]] || {
  echo "reconstructed archive member inventory differs" >&2
  exit 60
}
[[ "$RECONSTRUCTED_SHA256" == "$ORIGINAL_ARCHIVE_SHA256" && "$RECONSTRUCTED_SIZE" == "$ORIGINAL_ARCHIVE_SIZE" ]] || {
  echo "reconstructed archive does not reproduce the registered sequence 82 bytes exactly" >&2
  exit 60
}

RECEIPT_TEMP="$(mktemp "${RECONSTRUCTION_RECEIPT}.tmp.XXXXXX")"
printf 'schema_version=a38_terminal_evidence_reconstruction_v1\nsource_job_id=215801\nsource_receipt_sha256=%s\nsource_collector_sha256=%s\npatched_collector_sha256=%s\noriginal_archive_sha256=%s\noriginal_archive_size=%s\nreconstructed_archive=%s\nreconstructed_archive_sha256=%s\nreconstructed_archive_size=%s\nreconstructed_archive_member_count=%s\nreconstructed_archive_reserved_member_count=%s\nevaluation_array_reads=0\nformal_evaluation_outputs_created=0\n' \
  "$RESULT82_SHA256" "$SOURCE_COLLECTOR_SHA256" "$PATCHED_COLLECTOR_SHA256" \
  "$ORIGINAL_ARCHIVE_SHA256" "$ORIGINAL_ARCHIVE_SIZE" "$RECONSTRUCTED_ARCHIVE" \
  "$RECONSTRUCTED_SHA256" "$RECONSTRUCTED_SIZE" "$RECONSTRUCTED_MEMBER_COUNT" \
  "$RECONSTRUCTED_RESERVED_MEMBER_COUNT" > "$RECEIPT_TEMP"
mv -- "$RECEIPT_TEMP" "$RECONSTRUCTION_RECEIPT"
RECONSTRUCTION_RECEIPT_SHA256="$(sha256_file "$RECONSTRUCTION_RECEIPT")"
RECONSTRUCTION_RECEIPT_SIZE="$(stat -c '%s' "$RECONSTRUCTION_RECEIPT")"

printf 'SEQ89_A38_EVIDENCE_RECONSTRUCTION_COMPLETE source_job_id=215801 reconstructed_archive=%s reconstructed_archive_sha256=%s reconstructed_archive_size=%s reconstructed_archive_member_count=%s reconstructed_archive_reserved_member_count=%s receipt=%s receipt_sha256=%s receipt_size=%s evaluation_array_reads=0 formal_evaluation_outputs_created=0\n' \
  "$RECONSTRUCTED_ARCHIVE" "$RECONSTRUCTED_SHA256" "$RECONSTRUCTED_SIZE" \
  "$RECONSTRUCTED_MEMBER_COUNT" "$RECONSTRUCTED_RESERVED_MEMBER_COUNT" \
  "$RECONSTRUCTION_RECEIPT" "$RECONSTRUCTION_RECEIPT_SHA256" "$RECONSTRUCTION_RECEIPT_SIZE"
