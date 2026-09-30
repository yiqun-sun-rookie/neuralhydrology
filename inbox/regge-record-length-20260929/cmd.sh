#!/bin/bash
set -eo pipefail
sequence=32
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
CREDENTIALS=$ROOT/transport_credentials_005
export PYTHONDONTWRITEBYTECODE=1
date -Is
test ! -e "$ROOT/deploy/formal_calibration_capsule_005"
test ! -e "$ROOT/deploy/formal_calibration_capsule_005.tar.gz"
test ! -e "$ROOT/formal_calibration_005"
test ! -e "$ROOT/transport_package_005"
test ! -e "$CREDENTIALS"
test -x "$ROOT/runtime_probe_005/bin/python"
test "$(sha256sum "$ROOT/runtime_stage_005/runtime_ready.json" | awk '{print $1}')" = 93229f625533fbec6b0a04ddb70b3b47c3c725cab4a9f99aa4f97c1c9280f463
test "$(sha256sum "$ROOT/runtime_stage_005/pip_freeze.txt" | awk '{print $1}')" = 15fd95da01a1f5884aa4a225165942b43f5db405a4f0d75fd400dac6468a82ac
test -z "$(squeue -h -n regge_rl_cal_005 -o '%A')"
df -Pk "$ROOT"
sinfo -p hgpu2p -o '%P %a %l %D %t'
umask 077
mkdir "$CREDENTIALS"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$CREDENTIALS/upload_token_private.pem" 2>/dev/null
openssl pkey -in "$CREDENTIALS/upload_token_private.pem" -pubout -out "$CREDENTIALS/upload_token_public.pem"
chmod 600 "$CREDENTIALS/upload_token_private.pem"
echo HPC_PUBLIC_KEY_BEGIN
cat "$CREDENTIALS/upload_token_public.pem"
echo HPC_PUBLIC_KEY_END
sha256sum "$CREDENTIALS/upload_token_public.pem"
stat -c '%a' "$CREDENTIALS/upload_token_private.pem"
echo FIFTH_ATTEMPT_RESOURCE_AND_CREDENTIAL_GATE_COMPLETE
