#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/v09_strict
FORMAL=$ROOT/codetest/neuralhydrology/results/26_historical_band_experts/formal_v09
JID=$(cat $ROOT/predict_v09/predict_attempt_01_jobid.txt 2>/dev/null || echo "")

echo "=== A JOB ${JID} ==="
sacct -j "$JID" -X -P --format=JobID,JobName,State,ExitCode,Elapsed,Start,NodeList 2>&1 | head -4
echo "reason=$(squeue -j $JID -h -o '%r' 2>/dev/null || true)"
echo "est_start=$(squeue -j $JID -h --start -o '%S' 2>/dev/null || true)"

echo "=== B LOG ==="
for s in out err; do
  f=$ROOT/logs/predict_${JID}.${s}
  if [ -f "$f" ]; then
    echo "$f bytes=$(wc -c < $f) mtime=$(stat -c %y "$f")"
    tail -12 "$f"
  else
    echo "$f absent"
  fi
done

echo "=== C OUTPUT PROGRESS ==="
for p in predictions predictions.building; do
  if [ -e "$FORMAL/$p" ]; then echo "$p=present"; else echo "$p=absent"; fi
done
echo "seed_csv=$(ls $FORMAL/predictions.building/seeds/*.csv 2>/dev/null | wc -l)"
echo "ens_csv=$(ls $FORMAL/predictions.building/ensembles/*.csv 2>/dev/null | wc -l)"

echo "=== D PULL DIAGNOSTIC SCORER ==="
cd $ROOT/predict_v09/neuralhydrology || exit 1
git fetch origin "+codex/historical-band-experts-pilot:refs/remotes/origin/codex/historical-band-experts-pilot" -q
git reset -q --hard refs/remotes/origin/codex/historical-band-experts-pilot
echo "predict_repo_head=$(git rev-parse HEAD)"
echo "=== END ==="
