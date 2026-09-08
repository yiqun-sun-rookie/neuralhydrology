#!/bin/bash
# Read-only export of receiver evidence, chunk 1 of 4.
set -eo pipefail
EXPORTER=/data1/home/sunyiq/hpc_mailbox/inbox/id29-xinanjiang-transfer/export_receiver_chunk.py
printf '%s  %s\n' '6c25612aaa4f37a20d7a8e073af9411e027e2bbe7ccf693a55af4d1d003cfc36' "$EXPORTER" | sha256sum -c -
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B "$EXPORTER" --chunk-index 1 --chunk-count 4
