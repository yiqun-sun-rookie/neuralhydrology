#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
ARCHIVE="/data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels/DAILY_CAMELS_NATIVE_KALMANNET_FULL_STATE_A34_INFRA_RETRY2_SEQ25_evidence.tar.gz"
EXPECTED_SHA256="f384bfe61f43435449c130d3d589137f20eb9cedcd86518500bdd85ec165e41d"
EXPECTED_SIZE="255424"
EXPECTED_JOB_ID="212355"

sha256_file() { sha256sum "$1" | awk '{print $1}'; }

if [[ "${USER-}" != "$EXPECTED_USER" || "$(id -un)" != "$EXPECTED_USER" ]]; then
  echo "fixed-user check failed" >&2
  exit 50
fi
[[ -f "$ARCHIVE" && ! -L "$ARCHIVE" ]] || {
  echo "sequence-25 evidence archive absent or symbolic" >&2
  exit 51
}
[[ "$(stat -c '%s' "$ARCHIVE")" = "$EXPECTED_SIZE" ]] || {
  echo "sequence-25 evidence archive size differs" >&2
  exit 52
}
[[ "$(sha256_file "$ARCHIVE")" = "$EXPECTED_SHA256" ]] || {
  echo "sequence-25 evidence archive hash differs" >&2
  exit 53
}

AUDIT_DIRECTORY="$(mktemp -d /data1/home/sunyiq/kalmannet_a34_seq25_evidence_audit.XXXXXX)"
cleanup() {
  case "$AUDIT_DIRECTORY" in
    /data1/home/sunyiq/kalmannet_a34_seq25_evidence_audit.*)
      rm -rf -- "$AUDIT_DIRECTORY"
      ;;
    *)
      echo "refusing unsafe audit cleanup path" >&2
      return 91
      ;;
  esac
}
trap cleanup EXIT INT TERM

tar -xzf "$ARCHIVE" -C "$AUDIT_DIRECTORY"
if find "$AUDIT_DIRECTORY" -type l -print -quit | grep -q .; then
  echo "sequence-25 evidence contains a symbolic link" >&2
  exit 54
fi
mapfile -t TOP_LEVEL_DIRECTORIES < <(
  find "$AUDIT_DIRECTORY" -mindepth 1 -maxdepth 1 -type d -print
)
[[ "${#TOP_LEVEL_DIRECTORIES[@]}" -eq 1 ]] || {
  echo "sequence-25 evidence top-level geometry differs" >&2
  exit 55
}
EVIDENCE_ROOT="${TOP_LEVEL_DIRECTORIES[0]}"

echo "SEQ26_A34_SEQ25_EVIDENCE_AUDIT_IDENTITY"
printf 'archive=%s\narchive_sha256=%s\narchive_size=%s\nexpected_job_id=%s\n' \
  "$ARCHIVE" "$EXPECTED_SHA256" "$EXPECTED_SIZE" "$EXPECTED_JOB_ID"

echo "SEQ26_A34_SEQ25_EVIDENCE_FILE_MANIFEST_BEGIN"
find "$EVIDENCE_ROOT" -type f -printf '%P\t%s\n' | LC_ALL=C sort
echo "SEQ26_A34_SEQ25_EVIDENCE_FILE_MANIFEST_END"

emit_text_file() {
  local path="$1" relative size
  [[ -f "$path" && ! -L "$path" ]] || return 0
  size="$(stat -c '%s' "$path")"
  [[ "$size" -le 1048576 ]] || {
    printf 'SKIP_OVERSIZE\t%s\t%s\n' "$path" "$size"
    return 0
  }
  if ! grep -Iq . "$path" && [[ "$size" -gt 0 ]]; then
    printf 'SKIP_BINARY\t%s\t%s\n' "$path" "$size"
    return 0
  fi
  relative="${path#"$EVIDENCE_ROOT"/}"
  printf '\nSEQ26_FILE_BEGIN\t%s\t%s\n' "$relative" "$size"
  sed -n '1,500p' "$path"
  printf '\nSEQ26_FILE_END\t%s\n' "$relative"
}

while IFS= read -r -d '' path; do
  name="$(basename "$path")"
  case "$name" in
    *status*|*Status*|*sacct*|*slurm*|*stdout*|*stderr*|*.out|*.err|*.log|*exit*|*error*|*resource*|*evidence*|*completion*)
      emit_text_file "$path"
      ;;
  esac
done < <(
  find "$EVIDENCE_ROOT/status" "$EVIDENCE_ROOT/logs" -type f -print0 2>/dev/null |
    LC_ALL=C sort -z
)

echo
echo "SEQ26_LIVE_SACCT_BEGIN"
sacct -j "$EXPECTED_JOB_ID" --units=K --parsable2 \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,ReqMem,AllocTRES,MaxRSS,MaxVMSize ||
  true
echo "SEQ26_LIVE_SACCT_END"

echo "SEQ26_LIVE_SQUEUE_BEGIN"
squeue -j "$EXPECTED_JOB_ID" -o '%i|%T|%M|%R' || true
echo "SEQ26_LIVE_SQUEUE_END"

echo "SEQ26_A34_SEQ25_EVIDENCE_AUDIT_COMPLETE"
