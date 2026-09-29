#!/bin/bash
set -eo pipefail
sequence=14

ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
EVIDENCE=$ROOT/runtime_stage_005
KEYS=$ROOT/transport_credentials_001
TEST=$ROOT/transport_selftest_001

echo "=== bound runtime evidence ==="
sha256sum "$EVIDENCE/runtime_ready.json" "$EVIDENCE/pip_freeze.txt"
sed -n '1,120p' "$EVIDENCE/runtime_ready.json"

echo "=== exclusive authenticated-transport self-test ==="
test ! -e "$TEST"
mkdir "$TEST"
chmod 700 "$TEST"
cat > "$TEST/recipient.cnf" <<'EOF'
[req]
distinguished_name=dn
prompt=no
x509_extensions=ext
[dn]
CN=Regge HPC Transport Self Test
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,keyEncipherment
EOF
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -out "$TEST/recipient_private.pem" >/dev/null 2>&1
openssl req -new -x509 -sha256 -days 2 \
  -key "$TEST/recipient_private.pem" -config "$TEST/recipient.cnf" \
  -out "$TEST/recipient_certificate.pem"
printf 'regge authenticated transport self-test\n' > "$TEST/plain.bin"
openssl cms -encrypt -binary -aes-256-gcm -outform DER \
  -in "$TEST/plain.bin" -out "$TEST/payload.cms" \
  "$TEST/recipient_certificate.pem"
openssl cms -cmsout -inform DER -in "$TEST/payload.cms" -print \
  | grep -E 'authEnvelopedData|aes-256-gcm'
openssl cms -decrypt -binary -inform DER -in "$TEST/payload.cms" \
  -inkey "$TEST/recipient_private.pem" \
  -recip "$TEST/recipient_certificate.pem" \
  -out "$TEST/plain.decrypted.bin"
cmp "$TEST/plain.bin" "$TEST/plain.decrypted.bin"

echo '{"transport":"self-test"}' > "$TEST/manifest.json"
openssl dgst -sha256 -sign "$KEYS/upload_token_private.pem" \
  -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1 \
  -out "$TEST/manifest.sig" "$TEST/manifest.json"
openssl dgst -sha256 -verify "$KEYS/upload_token_public.pem" \
  -signature "$TEST/manifest.sig" \
  -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1 \
  "$TEST/manifest.json"
sha256sum "$KEYS/upload_token_public.pem" "$TEST/payload.cms" \
  "$TEST/manifest.json" "$TEST/manifest.sig"
echo "AUTHENTICATED_TRANSPORT_SELF_TEST_PASS"
