#!/bin/bash
# seq=81 READ-ONLY stage-3 prechecks b/c/V25-baseline (PLAN_20260916 v1 section 17): partition state + PriorityFlags,
# checkpoint/scaler/test_results.p inventory of the 26 stage-2 runs, combined sha256 of the six stage-2 forcing
# product directories (V25 baseline), new-root absence, channel seq. Nothing is written. No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
date "+epoch %s"
R2=/data1/home/sunyiq/precip_swap2_daily_2026_09
SH="$R2/data_shadow/camels_us/basin_mean_forcing"

echo "=== A. PARTITIONS hgpu4/hgpu8 and scheduler priority config ==="
sinfo -p hgpu4,hgpu8 -o '%.8P %.6a %.12l %.5D %.10T %N' 2>&1
echo "  sinfo rc=${PIPESTATUS[0]}"
echo "  hgpu4 queue: pending=$(squeue -p hgpu4 -h -t PD 2>/dev/null | wc -l) running=$(squeue -p hgpu4 -h -t R 2>/dev/null | wc -l); hgpu8 queue: pending=$(squeue -p hgpu8 -h -t PD 2>/dev/null | wc -l) running=$(squeue -p hgpu8 -h -t R 2>/dev/null | wc -l)"
scontrol show config 2>&1 | grep -iE 'PriorityType|PriorityFlags|PriorityDecayHalfLife|PriorityMaxAge|PriorityWeightAge|PriorityWeightFairShare|PriorityWeightJobSize|MaxJobCount|MaxArraySize'
echo "  scontrol rc=${PIPESTATUS[0]}"
sacctmgr show qos format=Name,MaxWall,MaxJobsPU,MaxSubmitPU,GrpTRES -P 2>&1 | head -12
echo "  sacctmgr rc=${PIPESTATUS[0]}"
echo "  hgpu4 max wall: $(sinfo -p hgpu4 -h -o '%l' 2>/dev/null | head -1)"

echo "=== B. STAGE-2 RUN INVENTORY (26 dirs; expect ep010=26 ep020=26 ep030=26 scaler=26) ==="
echo "  run dirs=$(ls -d $R2/runs/*_ep30 2>/dev/null | wc -l)"
echo "  model_epoch010.pt=$(ls $R2/runs/*_ep30/model_epoch010.pt 2>/dev/null | wc -l)  model_epoch020.pt=$(ls $R2/runs/*_ep30/model_epoch020.pt 2>/dev/null | wc -l)  model_epoch030.pt=$(ls $R2/runs/*_ep30/model_epoch030.pt 2>/dev/null | wc -l)"
echo "  train_data/train_data_scaler.yml=$(ls $R2/runs/*_ep30/train_data/train_data_scaler.yml 2>/dev/null | wc -l)  other files in train_data: $(ls $R2/runs/*_ep30/train_data/ 2>/dev/null | grep -v scaler | grep -v ':' | grep -v '^$' | sort -u | tr '\n' ' ')"
echo "  test_results.p count=$(ls $R2/runs/*_ep30/test/model_epoch030/test_results.p 2>/dev/null | wc -l) total_bytes=$(ls -l $R2/runs/*_ep30/test/model_epoch030/test_results.p 2>/dev/null | awk '{s+=$5} END {print s}')"
echo "  one weight file size: $(ls -l $R2/runs/ref_daymet_s100_*/model_epoch030.pt 2>/dev/null | awk '{print $5}') bytes"
echo "  runs/ total: $(du -sh $R2/runs 2>/dev/null | cut -f1)"

echo "=== C. V25 BASELINE: combined sha256 of stage-2 forcing product dirs (sorted per-file sha256 list hashed) ==="
for p in daymet era5l_refday imerg_refday imerg_utc gsmap_refday chirps imerg_uncal_refday; do
  d="$SH/$p"
  if [ -d "$d" ] || [ -L "$d" ]; then
    n=$(find -L "$d" -name '*_forcing_leap.txt' 2>/dev/null | wc -l)
    h=$(find -L "$d" -name '*_forcing_leap.txt' 2>/dev/null | sort | xargs sha256sum 2>/dev/null | awk '{print $1}' | sha256sum | cut -c1-16)
    echo "  $p files=$n combined=$h"
  else
    echo "  $p ABSENT"
  fi
done

echo "=== D. NEW ROOT ABSENT? / CHANNELS line ==="
ls -d /data1/home/sunyiq/precip_swap3_daily_2026_09 2>&1 | head -1
echo "  ls rc=${PIPESTATUS[0]} (expect non-zero = absent)"
grep -n 'attrswap-daily' ~/hpc_mailbox/CHANNELS.md 2>/dev/null | cut -c1-60
echo "  df /data1: $(df -h /data1 2>/dev/null | awk 'NR==2 {print $4" free of "$2}')"

echo "=== E. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
