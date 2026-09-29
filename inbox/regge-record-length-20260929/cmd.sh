#!/bin/bash
set -eo pipefail
sequence=13

ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
RUNTIME=$ROOT/runtime_probe_005
KEYS=$ROOT/transport_credentials_001

echo "=== exact runtime and tools ==="
test -x "$RUNTIME/bin/python"
"$RUNTIME/bin/python" -c 'import platform,numpy,pandas,torch; print(platform.python_version(),numpy.__version__,pandas.__version__,torch.__version__,torch.get_num_threads(),torch.cuda.is_available())'
command -v tar
command -v zstd
command -v openssl
command -v curl
zstd --version | sed -n '1p'
openssl version
curl --version | sed -n '1p'

echo "=== isolated target availability ==="
for target in \
  "$ROOT/deploy/formal_calibration_capsule_001" \
  "$ROOT/formal_calibration_001" \
  "$ROOT/transport_package_001" \
  "$KEYS"
do
  if [ -e "$target" ]; then
    echo "TARGET_ALREADY_EXISTS: $target"
    exit 1
  fi
  echo "AVAILABLE: $target"
done

echo "=== scheduler snapshot ==="
sinfo -p hgpu2p -N -O nodelist:12,statecompact:12,cpusstate:18,gres:16,gresused:24
squeue -u sunyiq -o '%.18i %.24j %.9P %.10T %.30R'

echo "=== storage ==="
df -h "$ROOT"

echo "=== create isolated upload-token keypair ==="
mkdir "$KEYS"
chmod 700 "$KEYS"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
  -out "$KEYS/upload_token_private.pem" >/dev/null 2>&1
chmod 600 "$KEYS/upload_token_private.pem"
openssl pkey -in "$KEYS/upload_token_private.pem" -pubout \
  -out "$KEYS/upload_token_public.pem" >/dev/null 2>&1
chmod 644 "$KEYS/upload_token_public.pem"
sha256sum "$KEYS/upload_token_public.pem"
echo "UPLOAD_TOKEN_PUBLIC_KEY_BEGIN"
sed -n '1,80p' "$KEYS/upload_token_public.pem"
echo "UPLOAD_TOKEN_PUBLIC_KEY_END"

echo "=== setup complete ==="
