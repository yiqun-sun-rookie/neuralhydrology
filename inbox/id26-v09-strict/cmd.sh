#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/v09_strict
SCORING=$ROOT/diagnostic_scoring
PREDICT_REPO=$ROOT/predict_v09/neuralhydrology
EXPECT=576d548253064699ade1e312ea875097d070557e3eef334874c310df61d8fd1e

echo "=== A STAGE ANSWER KEY (isolated dir, NOT the formal root) ==="
mkdir -p $SCORING
cp -f /data1/home/sunyiq/hpc_mailbox/payload/id26-v09-strict/track0_forcing_only_obs_eval.parquet $SCORING/
GOT=$(sha256sum $SCORING/track0_forcing_only_obs_eval.parquet | cut -d' ' -f1)
echo "answer_key_sha256=$GOT"
if [ "$GOT" != "$EXPECT" ]; then echo "ANSWER_KEY_HASH_DRIFT"; exit 1; fi
echo "answer_key=verified"
echo "scoring_dir_is_outside_formal_root=$(case $SCORING in *results/26_historical_band_experts*) echo NO;; *) echo YES;; esac)"

echo "=== B SYNC SCORER ==="
cd $PREDICT_REPO || exit 1
git fetch origin "+codex/historical-band-experts-pilot:refs/remotes/origin/codex/historical-band-experts-pilot" -q
git reset -q --hard refs/remotes/origin/codex/historical-band-experts-pilot
sed -i 's/\r$//' src/26_historical_band_experts/hpc/diagnostic_score_v09.slurm
echo "head=$(git rev-parse HEAD)"
echo "clean=[$(git status --porcelain --untracked-files=all)]"

echo "=== C SUBMIT ==="
rm -f $SCORING/diagnostic_score.json
out=$(sbatch src/26_historical_band_experts/hpc/diagnostic_score_v09.slurm 2>&1)
echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
if [ -z "$JID" ]; then echo "SUBMIT_FAILED"; exit 1; fi
echo "$JID" > $SCORING/score_jobid.txt
echo "jobid=$JID"
squeue -j "$JID" -h -o "%i %P %T %r" 2>&1 || true
echo "=== END ==="
