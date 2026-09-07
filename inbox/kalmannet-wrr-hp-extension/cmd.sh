#!/usr/bin/env bash
# Authorized exactly-once deployment of six validation-only replicas.
set -euo pipefail
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/finalist-replication-20260907
cd "$PAYLOAD"
sha256sum -c <<'TRANSPORT_HASHES'
266eab5e5f2b21b992d218aaede11abc6018c11a23c3c5c28a328bd5210a497e  payload/replication.tar.gz
8e9aa0c3769c050c070c6f48f1faa41aab94994f1a0791e89e35b92a44a8181e  PACKAGE_MANIFEST.json
da9dd01a449421ad96e76203afb373d88fd427d64e316a4e872767f80e48c6fe  REMOTE_BASELINE.json
3e62596c1431e2a7878103c4d166815ebc8e46ddd0c5c5d46de3ab1e84078d1e  REMOTE_SOURCE_MANIFEST.json
1d5cf545f0cdfdfbcdf33cca2adbba80309eef9470b0bd7a72b87230f2880a17  deploy_remote.py
TRANSPORT_HASHES
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B "$PAYLOAD/deploy_remote.py" --payload "$PAYLOAD" --submit
