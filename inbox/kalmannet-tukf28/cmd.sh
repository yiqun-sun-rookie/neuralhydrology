#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf28_20260902
JOB=218694

states() { sacct -j $JOB -n -P -X --format=State 2>/dev/null | sed 's/ .*//' | sort | uniq -c; }
bad() { sacct -j $JOB -n -P -X --format=JobID,State,ExitCode 2>/dev/null \
        | grep -E "FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL" | head -10; }

echo "=== EARLY CHECK (t+6 min) ==="
sleep 360
states
B=$(bad); if [ -n "$B" ]; then echo "EARLY FAILURES:"; echo "$B"
  echo "--- first error log ---"
  ls -t $ROOT/logs/tukf28_train_*.err 2>/dev/null | head -1 | xargs -r tail -25
  echo "EARLY_FAIL"; exit 1
fi
echo "no early failures"

echo "=== WAIT FOR TRAIN ARRAY (max 100 min more) ==="
for i in $(seq 1 100); do
  R=$(squeue -j $JOB -h -o "%T" 2>/dev/null | wc -l)
  [ "$R" -eq 0 ] && break
  sleep 60
done
echo "still in queue: ${R:-?}"
states
B=$(bad); if [ -n "$B" ]; then echo "FAILURES:"; echo "$B"; fi

echo "=== TRAIN RECORDS ==="
echo "train_json=$(ls $ROOT/results/train/*.json 2>/dev/null | wc -l) / 54"
python - <<'PY'
import glob, json, statistics as st
rows = [json.load(open(p)) for p in glob.glob(
    '/data1/home/sunyiq/kalmannet_tukf28_20260902/results/train/*.json')]
if not rows:
    print('NO RECORDS'); raise SystemExit(1)
for mode in ('sequential_leash', 'sequential_free'):
    d = [r for r in rows if r['mode'] == mode]
    if not d: continue
    zero = sum(1 for r in d if r['selected_update'] == 0)
    down = sum(1 for r in d if r['train_loss_trace'][-1] < r['train_loss_trace'][0])
    repro = {}
    for r in d: repro[r['start_reproduction']] = repro.get(r['start_reproduction'], 0) + 1
    hits = [r['leash_hits'] for r in d if r['leash_hits'] is not None]
    print('%-18s n=%2d  zero_update=%d  loss_down=%d  drift_med=%.3f  rss_max=%.0fMB  start_repro=%s%s'
          % (mode, len(d), zero, down,
             st.median([r['drift_at_checkpoint'] for r in d]),
             max(r['peak_rss_mb'] or 0 for r in d), repro,
             '  leash_hit_basins=%d' % sum(1 for h in hits if h > 0) if hits else ''))
    if any(not r.get('noise_frozen_verified') for r in d):
        print('  ** NOISE FROZEN CHECK FAILED **')
PY

if [ "$(ls $ROOT/results/train/*.json 2>/dev/null | wc -l)" -ne 54 ]; then
  echo "TRAIN_INCOMPLETE"; exit 1
fi
echo "=== SBATCH READOUT ARRAY 189 ==="
cd $ROOT || exit 1
sbatch $ROOT/slurm/tukf28_readout.slurm || exit 1
echo SEQ4_OK
