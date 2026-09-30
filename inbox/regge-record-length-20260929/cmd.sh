#!/bin/bash
set -eo pipefail

sequence=26
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
test -d "$ROOT"
for path in "$ROOT/deploy/formal_calibration_capsule_004" \
    "$ROOT/formal_calibration_004" "$ROOT/transport_package_004" \
    "$ROOT/transport_credentials_004" "$ROOT/submission_004"; do
  if [ -e "$path" ]; then
    echo "EXCLUSIVE_TARGET_EXISTS=$path"
    exit 1
  fi
done
date -Is
df -Pk "$ROOT"
sinfo -p hgpu2p -N -h -o '%N %T %c %m %e %O'
squeue -u sunyiq -h -o '%i %j %P %T %R'
sha256sum "$ROOT/runtime_stage_005/runtime_ready.json" \
  "$ROOT/runtime_stage_005/pip_freeze.txt"
test -x "$ROOT/runtime_probe_005/bin/python"
command -v openssl
command -v zstd
umask 077
mkdir "$ROOT/transport_credentials_004"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
  -out "$ROOT/transport_credentials_004/upload_token_private.pem" 2>/dev/null
openssl pkey -in "$ROOT/transport_credentials_004/upload_token_private.pem" \
  -pubout -out "$ROOT/transport_credentials_004/upload_token_public.pem"
echo HPC_SIGNING_PUBLIC_BEGIN
cat "$ROOT/transport_credentials_004/upload_token_public.pem"
echo HPC_SIGNING_PUBLIC_END
sha256sum "$ROOT/transport_credentials_004/upload_token_public.pem"
echo FOURTH_ATTEMPT_TARGETS_AND_CREDENTIALS_READY
