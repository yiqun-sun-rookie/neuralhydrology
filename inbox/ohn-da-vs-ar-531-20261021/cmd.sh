#!/bin/bash
# Fix A1 training (246279 failed: find on missing runs/ + pipefail -> silent exit 1). Own root only.
# Back up old script, install fixed one (mkdir before find; -p hgpu2p,hgpu2,hgpu4; --exclude=ngu002; %3), resubmit,
# re-point held A1+DA 246280 to the new job and release it.
set -o pipefail
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
cd $NEW || exit 1
date --iso-8601=seconds
cp -n slurm/p2_a1_train.slurm slurm/p2_a1_train.slurm.bak_246279 && echo BACKUP_OK
echo 'IyEvdXNyL2Jpbi9lbnYgYmFzaAojU0JBVENIIC1KIG9obl9hMV90cmFpbgojU0JBVENIIC1wIGhncHUycCxoZ3B1MixoZ3B1NAojU0JBVENIIC0tZXhjbHVkZT1uZ3UwMDIKI1NCQVRDSCAtTiAxCiNTQkFUQ0ggLW4gMQojU0JBVENIIC0tY3B1cy1wZXItdGFzaz00CiNTQkFUQ0ggLS1ncmVzPWdwdToxCiNTQkFUQ0ggLXQgMS0xMjowMDowMAojU0JBVENIIC0tYXJyYXk9MC00JTMKI1NCQVRDSCAtbyAvZGF0YTEvaG9tZS9zdW55aXEvb2huX2RhX3ZzX2FyXzUzMV8yMDI2MTAyMS9sb2dzLyV4LSVBXyVhLm91dAojU0JBVENIIC1lIC9kYXRhMS9ob21lL3N1bnlpcS9vaG5fZGFfdnNfYXJfNTMxXzIwMjYxMDIxL2xvZ3MvJXgtJUFfJWEuZXJyCiMgUDIgQTEgKHBsYW4gdjIgwqc0KTogaWQxOF9uc2UgKyBRT0JTIGlucHV0ICsgaW5wdXRfcmVwbGFjaW5nLCBzZWVkcyAxMDAuLjEwNDsgZnVsbCB0cmFpbmluZyB0aGVuIHRlc3QtcGVyaW9kIGluZmVyZW5jZS4KIyBPcmlnaW5hbCBpZDE4X25zZSB0cmFpbmluZ3MgdG9vayAxMC0xMi42IGggKEE4MDAvQTQwKTsgMzYgaCB3YWxsIGxpbWl0IGxlYXZlcyBtYXJnaW4gb24gUlRYIDMwOTAuCnNldCAtZW8gcGlwZWZhaWwKc291cmNlIC9kYXRhMS9ob21lL3N1bnlpcS9vaG5fZGFfdnNfYXJfNTMxXzIwMjYxMDIxL2NvZGUvY29tbW9uX2Vudi5zaApTRUVEPSQoKDEwMCArIFNMVVJNX0FSUkFZX1RBU0tfSUQpKQpOQU1FPSJhMV9zJHtTRUVEfSIKZWNobyAiaG9zdD0kKGhvc3RuYW1lKSBzdGFydD0kKGRhdGUgLS1pc28tODYwMT1zZWNvbmRzKSBqb2I9JHtTTFVSTV9BUlJBWV9KT0JfSUR9XyR7U0xVUk1fQVJSQVlfVEFTS19JRH0gbmFtZT0kTkFNRSIKZ3B1X2NoZWNrClsgLWYgIiRORVcvbG9ncy9kb25lXyROQU1FIiBdICYmIHsgZWNobyAiQUxSRUFEWV9ET05FICROQU1FIjsgZXhpdCAwOyB9Cm1rZGlyIC1wICIkTkVXL3J1bnMiICAjIGJlZm9yZSBmaW5kOiBmaW5kIG9uIGEgbWlzc2luZyBkaXIgZmFpbHMgdGhlIHBpcGVsaW5lIGFuZCBzZXQgLWUgZXhpdHMgc2lsZW50bHkgKGpvYiAyNDYyNzkpCk5fT0xEPSQoZmluZCAiJE5FVy9ydW5zIiAtbWF4ZGVwdGggMSAtdHlwZSBkIC1uYW1lICIke05BTUV9XyoiIDI+L2Rldi9udWxsIHwgd2MgLWwpClsgIiROX09MRCIgLWVxIDAgXSB8fCB7IGVjaG8gIlNUQUxFX1JVTl9ESVIgJE5BTUUgKCROX09MRCkgLSBub3Qgb3ZlcndyaXRpbmciOyBleGl0IDQ7IH0KcHl0aG9uIC11ICIkTkVXL2NvZGUvbWFrZV9hMV9jb25maWcucHkiICIkT0xEL2NvbmZpZ3MvaWQxOF9uc2UueW1sIiAiJE5FVy9jb25maWdzLyROQU1FLnltbCIgIiROQU1FIiBcCiAgIiRORVcvcnVucyIgIiRORVcvZGF0YS9keW5fYTEiICIkU0VFRCIKZ3JlcCAtbkUgJ14oZXhwZXJpbWVudF9uYW1lfHNlZWR8bmFuX2hhbmRsaW5nX21ldGhvZHxkeW5hbWljc19kYXRhX2RpcnxlcG9jaHMpOicgIiRORVcvY29uZmlncy8kTkFNRS55bWwiCnJ1bl9jbGkgdHJhaW4gLS1jb25maWctZmlsZSAiJE5FVy9jb25maWdzLyROQU1FLnltbCIKUlVOPSQoZmluZCAiJE5FVy9ydW5zIiAtbWF4ZGVwdGggMSAtdHlwZSBkIC1uYW1lICIke05BTUV9XyoiKQpbICIkKGVjaG8gIiRSVU4iIHwgd2MgLWwpIiAtZXEgMSBdIHx8IHsgZWNobyAiUlVOX0RJUl9BTUJJR1VPVVMgJFJVTiI7IGV4aXQgNTsgfQpydW5fY2xpIGluZmVyIC0tcnVuLWRpciAiJFJVTiIKbHMgIiRSVU4iL3Rlc3QvbW9kZWxfZXBvY2gwNTAvCmRhdGUgLS1pc28tODYwMT1zZWNvbmRzID4gIiRORVcvbG9ncy9kb25lXyROQU1FIgplY2hvICJBMV9UUkFJTl9ET05FICROQU1FICQoZGF0ZSAtLWlzby04NjAxPXNlY29uZHMpIgo=' | base64 -d > slurm/p2_a1_train.slurm.new
S=$(sha256sum slurm/p2_a1_train.slurm.new | cut -c1-64)
[ "$S" = "bc652f80c8e3bb3a54d11e5445518e0952f96e4b1384de75ec1f04ab057821e2" ] || { echo "SHA_MISMATCH $S"; exit 2; }
mv slurm/p2_a1_train.slurm.new slurm/p2_a1_train.slurm
grep -nE '^#SBATCH (-p|--exclude|--array)|^mkdir' slurm/p2_a1_train.slurm
mkdir -p runs
ls runs | grep -c '^a1_' ; ls logs | grep -c '^done_a1_'
OUT=$(sbatch slurm/p2_a1_train.slurm 2>&1); echo "SBATCH: $OUT"
J=$(echo "$OUT" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
[ -n "$J" ] || { echo "SUBMIT_FAILED"; exit 3; }
echo "p2_a1_train_retry $J $(date --iso-8601=seconds) (replaces 246279: runs/ mkdir bug)" >> logs/submissions.txt
scontrol update jobid=246280 Dependency=afterany:$J 2>&1 && echo "DEP_UPDATED 246280 -> afterany:$J"
scontrol release 246280 2>&1 && echo "RELEASED 246280"
echo "NEW_A1=$J"
squeue -j $J,246280,246281 -h -o '%i|%T|%P|%R|%l' 2>&1 | head -6
for X in 246280 246281; do scontrol show job $X 2>/dev/null | grep -oE 'Dependency=[^ ]*' | head -1; done
echo "SEQ29_DONE"
