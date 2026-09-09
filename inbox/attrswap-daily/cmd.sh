#!/bin/bash
# URGENT read-mostly: cancel the three era5l arms, which are training on a wrongly-built forcing product.
# Root cause: the builder assumed PRCP sits at tab field 2 in the source product too, but the era5l_caravan
# files have six fields (date, PRCP, SRAD, Tmax, Tmin, Vp) so field 2 is SRAD. The chirps arms are unaffected.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap_daily_2026_09
echo "=== A. EVIDENCE: header of each product ==="
for p in maurer era5l_caravan chirps era5l_precip; do
  f=$(find -L "$R/data_shadow/camels_us/basin_mean_forcing/$p" -name '01022500_*_forcing_leap.txt' 2>/dev/null | head -1)
  [ -n "$f" ] && { echo "--- $p ---"; sed -n '4p' "$f"; sed -n '5p' "$f"; }
done
echo "=== B. CANCEL THE THREE era5l ARMS (explicit ids) ==="
for j in 224463 224464 224465; do
  st=$(sacct -j "$j" -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
  scancel "$j" && echo "  已取消 $j（状态曾为 $st）"
done
echo "=== C. CHIRPS 三臂保持运行（其构建正确：比值 0.98、滞后分布与本地实测一致）==="
squeue -u "$USER" -o '%.11i %.24j %.9T %.10M %.9N' 2>&1 | grep -Ei 'pswap|JOBID' || echo '  (none)'
echo "=== D. 隔离错误产物（改名不删）==="
mv "$R/data_shadow/camels_us/basin_mean_forcing/era5l_precip" \
   "$R/data_shadow/camels_us/basin_mean_forcing/BAD_era5l_precip_$(date +%Y%m%d_%H%M%S)" \
  && echo "  错误产物已改名隔离"
mv "$R/logs/build_era5l_precip.json" "$R/logs/build_era5l_precip.BAD.json" 2>/dev/null
echo "=== DONE ==="
