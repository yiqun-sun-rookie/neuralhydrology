#!/bin/bash
# a02b seq=4 : verify the authoritative results under $PKG/runs (never touched by git).
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02

echo "=== A RUNS DIR ==="
timeout 30 ls -la "$PKG/runs/" 2>&1 | sed 's/^/  /'

echo "=== B PER-RUN ARTIFACTS ==="
timeout 60 bash -c 'for d in '"$PKG"'/runs/a02_*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  ck=$([ -f "$d/best_model.pt" ] && du -h "$d/best_model.pt" | cut -f1 || echo MISSING)
  bm=$([ -f "$d/best_metrics.json" ] && echo yes || echo MISSING)
  hs=$([ -f "$d/train_history.jsonl" ] && wc -l < "$d/train_history.jsonl" || echo MISSING)
  printf "  %-26s ckpt=%-7s best_metrics=%-8s history_lines=%s\n" "$n" "$ck" "$bm" "$hs"
done' 2>&1

echo "=== C BEST METRICS CONTENT (completed runs) ==="
timeout 40 bash -c 'for d in '"$PKG"'/runs/a02_*/; do
  [ -f "$d/best_metrics.json" ] || continue
  printf "  %-26s %s\n" "$(basename $d)" "$(head -c 400 $d/best_metrics.json | tr -d "\n ")"
done' 2>&1

echo "=== D DISK SPACE ==="
timeout 20 df -h /data1 2>&1 | tail -2 | sed 's/^/  /'
timeout 30 du -sh "$PKG/runs" 2>&1 | sed 's/^/  /'
