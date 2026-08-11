#!/bin/bash
set -euo pipefail

MAILBOX=/data1/home/sunyiq/hpc_mailbox
SOURCE_BRANCH=codex/unified-autoresearch-vertical
SOURCE_COMMIT=85ae470c9c08a62abd402f082ecc692cfe203294
BUILDER_PAYLOAD="$MAILBOX/inbox/autoresearch-64/payload/unseen64_builder_85ae470c_seq65.tar.gz"
TEMPLATE="$MAILBOX/inbox/autoresearch-64/hbv_lite_unseen_64_confirmation_seq65.slurm"
SUBMIT_SCRIPT=/tmp/autoresearch64-unseen64-seq65.slurm
RECEIPT=/tmp/autoresearch64-unseen64-seq65.receipt
LOCK=/tmp/autoresearch64-unseen64-seq65.lock

exec 9>"$LOCK"
flock 9
if [ -s "$RECEIPT" ]; then
  cat "$RECEIPT"
  exit 0
fi

cd "$MAILBOX"
git fetch origin "$SOURCE_BRANCH"
ACTUAL_COMMIT=$(git rev-parse FETCH_HEAD)
test "$ACTUAL_COMMIT" = "$SOURCE_COMMIT"

if [ ! -e "$BUILDER_PAYLOAD" ]; then
  TEMP_PAYLOAD="${BUILDER_PAYLOAD}.tmp.$$"
  git archive --format=tar FETCH_HEAD | gzip -n > "$TEMP_PAYLOAD"
  chmod 0444 "$TEMP_PAYLOAD"
  mv "$TEMP_PAYLOAD" "$BUILDER_PAYLOAD"
fi
BUILDER_PAYLOAD_SHA256=$(sha256sum "$BUILDER_PAYLOAD" | awk '{print $1}')

sed \
  -e "s/__BUILDER_PAYLOAD_SHA256__/$BUILDER_PAYLOAD_SHA256/g" \
  "$TEMPLATE" > "$SUBMIT_SCRIPT"
bash -n "$SUBMIT_SCRIPT"

JOB_ID=$(sbatch --parsable "$SUBMIT_SCRIPT")
printf 'job_id=%s\nsource_commit=%s\nbuilder_payload_sha256=%s\n' \
  "$JOB_ID" "$SOURCE_COMMIT" "$BUILDER_PAYLOAD_SHA256" > "$RECEIPT"
cat "$RECEIPT"
