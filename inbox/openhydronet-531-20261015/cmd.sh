#!/bin/bash
set -o pipefail
# seq 29: move my own two PENDING screening jobs from hgpu8 (nodes unavailable) to hgpu4; touches no other job
date --iso-8601=seconds
for J in 245671 245672; do
  N=$(squeue -j $J -h -o '%j %T' 2>/dev/null)
  echo "before: $J $N"
  case "$N" in
    ohn_tune_v0\ PENDING|ohn_tune_v1\ PENDING) scontrol update JobId=$J Partition=hgpu4 && echo "moved $J -> hgpu4" ;;
    *) echo "skip $J (not my pending tune job)";;
  esac
done
sleep 20
squeue -u sunyiq -h -o '%.10i %.16j %.9T %.8P %R' | grep -E ' ohn_tune' || true
exit 0
