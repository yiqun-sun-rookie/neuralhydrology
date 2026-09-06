#!/usr/bin/env bash
set -o pipefail
echo "=== STAMP ==="; date -Is
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ID33"
echo "=== A. UTIL HISTOGRAM ==="
for f in logs/33_transformer_recipe_repair/utilisation-222800.csv logs/33_transformer_recipe_repair/utilisation-222801.csv; do
  test -f "$f" || continue
  echo "-- $f"
  awk -F, 'NR>1{b=int($2/10)*10; h[b]++; n++} END{for(i=0;i<=100;i+=10) if(h[i]) printf("   %3d-%3d%%: %4d (%.1f%%)\n",i,i+9,h[i],100*h[i]/n)}' "$f" || true
  echo "   first zero-util sample:"; awk -F, 'NR>1 && $2+0==0 {print "   "$0; exit}' "$f" || true
  echo "   last nonzero-util sample:"; awk -F, 'NR>1 && $2+0>0 {l=$0} END{print "   "l}' "$f" || true
done
echo "=== B. ARM TIMELINE (222800 packed) ==="
grep -hE "ARM|START|FINISH|=== " logs/33_transformer_recipe_repair/packed-222800.out 2>/dev/null | head -40 || true
echo "=== C. RUN DIR MTIMES ==="
for a in T1 T2 T3 T4 T5 L33; do
  d=$(ls -1d results/33_transformer_recipe_repair/$a/*/ 2>/dev/null | tail -1)
  [ -n "$d" ] && echo "  $a $(stat -c '%y' "$d"validation/model_epoch030 2>/dev/null)"
done
echo DONE
