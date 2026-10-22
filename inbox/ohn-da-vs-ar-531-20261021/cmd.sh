#!/bin/bash
# OHN embedding-DA vs AR (plan v2, user-approved 2026-10-21/22). seq1: read-only probes; deploy code to a NEW root;
# submit the two P1 smoke jobs (DA smoke on the TRAINING period only; A1 1-epoch smoke). Old root is read-only.
set -o pipefail
CH=ohn-da-vs-ar-531-20261021
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
OLD=/data1/home/sunyiq/openhydronet_531_20261015
PAY=$HOME/hpc_mailbox/inbox/$CH/payload/payload_v1.tar.gz
EXP_SHA=2738e1fdd26b2ed762107ffa2eda5d5ca8c02b72f7141eab301693ceffe099fb
date --iso-8601=seconds

echo "=== OLD RUNS (read-only) ==="
for D in $(ls -d "$OLD"/runs/id18_nse* "$OLD"/runs/tune_v0_* 2>/dev/null); do
  echo "--- $(basename "$D")"
  ls "$D" | tr '\n' ' '; echo
  ls -la "$D"/model_epoch050.pt 2>/dev/null | awk '{print "weights50 bytes="$5}'
  ls -d "$D"/test/model_epoch0*/test_results*.zarr 2>/dev/null || echo "NO_TEST_ZARR"
  grep -nE '^(seed|experiment_name|run_dir|device):' "$D/config.yml" 2>/dev/null | tr '\n' ' '; echo
done
echo "=== BASIN FILE ==="
head -3 "$OLD/data/id18_basins_531.txt"; wc -l < "$OLD/data/id18_basins_531.txt"
ls -d "$OLD/data/id18_maurer/streamflow.zarr" "$OLD/data/id18_maurer/dynamics/MAURER" "$OLD/configs/id18_nse.yml" "$OLD/src/flood-forecasting/googlehydrology/evaluation/assimilation.py"
echo "=== PAST JOB DURATIONS (read-only) ==="
sacct -X -n -P -j 243187,244040,244041,244042,244043,245671 --format=JobID,JobName,Partition,State,Elapsed,NodeList 2>&1
echo "=== GPU PARTITIONS ==="
for P in hgpu8 hgpu4 hgpu2p hgpu2; do
  echo "--- $P"; sinfo -p $P -N -h -O nodelist:10,statecompact:10,gres:14,gresused:24 2>&1
done
echo "n_my_jobs=$(squeue -u $USER -h | wc -l)"

echo "=== DEPLOY ==="
[ -e "$NEW" ] && { echo "NEW_ROOT_EXISTS -- stopping before any sbatch"; ls -la "$NEW"; exit 1; }
[ -f "$PAY" ] || { echo "PAYLOAD_MISSING"; exit 1; }
GOT=$(sha256sum "$PAY" | cut -d' ' -f1); [ "$GOT" = "$EXP_SHA" ] || { echo "PAYLOAD_SHA_MISMATCH $GOT"; exit 1; }
mkdir -p "$NEW"/logs "$NEW"/copies "$NEW"/data "$NEW"/results || exit 1
tar -xzkf "$PAY" -C "$NEW" 2>&1 | grep -v 'implausibly old' || true
cd "$NEW" || exit 1
sha256sum -c MANIFEST.sha256 > logs/manifest_v1.txt 2>&1 || { echo MANIFEST_FAILED; cat logs/manifest_v1.txt; exit 1; }
echo "manifest OK $(grep -c ': OK$' logs/manifest_v1.txt) files"
grep -c $'\r' slurm/*.slurm code/*.sh | tr '\n' ' '; echo

echo "=== SUBMIT P1 SMOKES ==="
for S in p1_smoke_da p1_smoke_a1; do
  touch "logs/submission_started_$S"
  out=$(sbatch "slurm/$S.slurm" 2>&1); echo "$out" | head -3
  jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  [ -n "$jid" ] || { echo "SUBMIT_FAILED $S"; exit 1; }
  echo "$S $jid $(date --iso-8601=seconds)" >> logs/submissions.txt
done
cat logs/submissions.txt
squeue -u $USER -h -o '%i %P %T %j %R' | grep ohn_ || true
echo "SEQ1_DONE"
