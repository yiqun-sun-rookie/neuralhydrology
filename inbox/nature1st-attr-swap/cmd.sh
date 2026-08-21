#!/bin/bash
# nature1st-attr-swap seq=63 -- READ-ONLY. No sbatch, no writes.
# armE/armF verdicts are in (seq=62). Next arm is armG "China-supplyable" -- 17 attributes
# built locally today. Before shipping it I need to know how this run dir is kept in sync
# and whether anything of armG/armH is already up here.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st

echo "=== A. RUN DIR + SYNC MECHANISM ==="
ls -d "$RUN" 2>&1
cd "$RUN" 2>/dev/null || { echo "RUN DIR MISSING"; exit 1; }
echo "-- is it a git repo? --"
git rev-parse --is-inside-work-tree 2>&1 | head -1
git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>&1 | head -1
git log --oneline -3 2>&1 | head -3
echo "-- remotes --"
git remote -v 2>&1 | head -4
echo "-- how many uncommitted --"
git status --porcelain 2>/dev/null | wc -l

echo "=== B. DO armG/armH ARTEFACTS EXIST HERE? ==="
for f in \
  data/interim/stage_static_feature_stats_armG.json \
  data/interim/stage_static_feature_stats_armH.json \
  data/processed/station_meta/trainable_mountain_stations_armG.csv \
  data/processed/station_meta/trainable_mountain_stations_armH.csv \
  scripts/chain_prepare_attrset_extended.py \
  scripts/hpc_train_q_armG_china_supplyable.sbatch \
  scripts/hpc_train_q_armH_china_supplyable_log.sbatch ; do
  if [ -f "$f" ]; then printf 'PRESENT  %s  %s\n' "$(stat -c%s "$f")" "$f"; else printf 'ABSENT   %s\n' "$f"; fi
done

echo "=== C. WHAT IS ALREADY HERE (the arms that ran) ==="
ls -1 data/interim/stage_static_feature_stats_*.json 2>&1 | head -12
ls -1 data/processed/station_meta/trainable_mountain_stations_*.csv 2>&1 | head -12
ls -1 scripts/chain_prepare_attrset.py scripts/chain_train_q_attrset.py scripts/chain_eval_q_attrset.py 2>&1

echo "=== D. SOURCE TABLE FOR THE TWO NEW COLUMNS ==="
# armG needs sgr_dk_sav and lkv_mc_usu, which come from the raw HydroATLAS table.
for c in /data1/home/sunyiq/neuralhydrology/data/camelsh/attributes_gageii/attributes_hydroATLAS.csv ; do
  if [ -f "$c" ]; then printf 'PRESENT  %s  %s\n' "$(stat -c%s "$c")" "$c"; else printf 'ABSENT   %s\n' "$c"; fi
done

echo "=== E. SPLITS FILE (stats must be train-only) ==="
ls -la data/interim/stage_station_splits.json 2>&1
md5sum data/interim/stage_station_splits.json data/interim/stage_static_feature_stats.json 2>&1

echo "=== F. FINISHED ARM DIRS ==="
for d in q_lstm_control_hpc_s42 q_lstm_hydroatlas_hpc_s42 q_lstm_usminus4_hpc_s42 \
         q_lstm_globalplus4_hpc_s42 q_lstm_armE_hpc_s42 q_lstm_armF_hpc_s42 ; do
  printf '%-28s %s\n' "$d" "$([ -f models/$d/best_metrics.json ] && cat models/$d/best_metrics.json | tr -d '\n ' | head -c 120 || echo MISSING)"
done

echo "=== G. DISK ==="
df -h /data1 2>&1 | tail -1
echo "=== END seq=63 ==="
