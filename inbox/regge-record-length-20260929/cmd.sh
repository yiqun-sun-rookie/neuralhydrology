#!/bin/bash
set -eo pipefail

sequence=18
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
CREDENTIALS=$ROOT/transport_credentials_002

test ! -e "$CREDENTIALS"
umask 077
mkdir "$CREDENTIALS"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
  -out "$CREDENTIALS/upload_token_private.pem"
openssl pkey -in "$CREDENTIALS/upload_token_private.pem" -check -noout
openssl pkey -in "$CREDENTIALS/upload_token_private.pem" -pubout \
  -out "$CREDENTIALS/upload_token_public.pem"
test "$(stat -c '%a' "$CREDENTIALS/upload_token_private.pem")" = "600"

echo "HPC_SIGNING_CREDENTIALS_002_READY=1"
sha256sum "$CREDENTIALS/upload_token_public.pem"
openssl pkey -pubin -in "$CREDENTIALS/upload_token_public.pem" -text -noout \
  | head -n 1
echo "---BEGIN_PUBLIC_KEY_002---"
cat "$CREDENTIALS/upload_token_public.pem"
echo "---END_PUBLIC_KEY_002---"
