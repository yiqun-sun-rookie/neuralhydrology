#!/bin/bash
# seq=71 AUDIT-2b: dump the raw per-epoch loss lines (seq=70 regexes did not match nh's log format) + iteration counts from slurm/tqdm output.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
echo "=== LOG DIRS ==="; ls logs/33_transformer_recipe_repair 2>/dev/null | head -40; ls results/33_transformer_recipe_repair/G1/*/ | head -30
d0=$(ls -d results/33_transformer_recipe_repair/G1/*_2026_* | tail -1)
echo "=== SAMPLE output.log (G1) first 25 lines + lines with 'average' (first 4) ==="; head -25 "$d0/output.log"; grep -n -m4 -i "average\|median" "$d0/output.log"
for a in G1 G1_s200 G1_s300 G1_s400 G1_s500 G1_s600 G1_s700 G1_s800 C4 C4_s200 C4_s300 C4_s400 C4_s500 C4_s600 C4_s700 C4_s800; do
  d=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_* 2>/dev/null | tail -1)
  echo "##ARM $a"
  grep -i "average" "$d/output.log" | sed 's/^.*Epoch/Epoch/' 
  # tqdm iteration count from any log mentioning this arm's run dir
  for f in $(grep -l -- "$(basename "$d")" logs/33_transformer_recipe_repair/* 2>/dev/null | head -3); do
    echo "  tqdm@$f: $(tr '\r' '\n' < "$f" | grep -o 'Epoch 1: 100%[^|]*|[^|]*| [0-9]*/[0-9]*' | head -1 | grep -o '[0-9]*/[0-9]*$')"
  done
done
echo "=== DONE ==="
