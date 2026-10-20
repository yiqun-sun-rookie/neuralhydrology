#!/bin/bash
set -eo pipefail
KEY_ROOT=/data1/home/sunyiq/regge_experiments/REGGE-PQX01-FROZEN-QE-CROSSBANK/20261020-v01-transfer
if [ -e "$KEY_ROOT" ]; then
    test -s "$KEY_ROOT/transfer_private.pem"
    test -s "$KEY_ROOT/transfer_public.pem"
else
    umask 077
    mkdir -p "$(dirname "$KEY_ROOT")"
    mkdir "$KEY_ROOT"
    openssl genrsa -out "$KEY_ROOT/transfer_private.pem" 2048
    openssl rsa -in "$KEY_ROOT/transfer_private.pem" -pubout -out "$KEY_ROOT/transfer_public.pem"
fi
chmod 700 "$KEY_ROOT"
chmod 600 "$KEY_ROOT/transfer_private.pem"
printf 'PUBLIC_KEY_BEGIN\n'
cat "$KEY_ROOT/transfer_public.pem"
printf 'PUBLIC_KEY_END\n'
openssl version
test ! -e /data1/home/sunyiq/regge_experiments/REGGE-PQX01-FROZEN-QE-CROSSBANK/20261020-v01
printf 'EXPERIMENT_ROOT_STILL_ABSENT\n'
