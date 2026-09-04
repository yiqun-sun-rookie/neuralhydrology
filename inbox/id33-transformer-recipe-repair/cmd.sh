#!/usr/bin/env bash
# ID33 seq=7 : is anything of mine HELD but not USED? Read-only.
set -o pipefail
echo "=== STAMP ==="; date -Is
NOW=$(date +%s)

echo "=== A. WHAT I HOLD (AllocTRES per running job) ==="
for J in 220490 220491 220492 220493 220494 220495 220658 220659; do
  line=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | grep -E '^(JobId|JobState|NumCPUs|NumNodes|TRES|StdOut|NodeList)=' | tr '\n' ' ')
  echo "  $line"
done

echo "=== B. LOG STALENESS (the documented silent-stall signature) ==="
for J in 220490 220491 220492 220493 220494 220495 220658 220659; do
  ST=$(squeue -j "$J" -h -o "%t" 2>/dev/null)
  SO=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdOut=//p' | head -1)
  if [ "$ST" = "R" ] && [ -n "$SO" ] && [ -f "$SO" ]; then
    AGE=$(( NOW - $(stat -c %Y "$SO") ))
    FLAG=OK; [ "$AGE" -gt 3600 ] && FLAG="SUSPECT_STALL"
    echo "  job=$J state=$ST idle_seconds=$AGE $FLAG"
  else
    echo "  job=$J state=${ST:-notqueued} (no running stdout to age)"
  fi
done

echo "=== C. ARE THE TRAINING LOGS ACTUALLY ADVANCING ==="
R=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo/results/33_transformer_recipe_repair
for a in T1 T2 T3 T4 T5 L33 C1 C2; do
  f=$(find "$R/$a" -name output.log -type f 2>/dev/null | head -1)
  if test -n "$f"; then
    AGE=$(( NOW - $(stat -c %Y "$f") ))
    n=$(grep -c 'average validation loss' "$f" 2>/dev/null || true)
    last=$(grep 'Median validation metrics' "$f" 2>/dev/null | tail -1 | sed 's/.*NSE: //')
    echo "  $a: epochs=${n:-0} last_NSE=${last:-none} log_idle=${AGE}s"
  else echo "  $a: no log"; fi
done

echo "=== D. EPOCH WALL TIME (is the larger batch actually using the card?) ==="
for a in T1 T4; do
  f=$(find "$R/$a" -name output.log -type f 2>/dev/null | head -1)
  test -n "$f" && { echo "  -- $a --"; grep -oE '^[0-9-]+ [0-9:]+.*Epoch [0-9]+ average loss' "$f" 2>/dev/null | awk '{print $1,$2,$NF,$4}' | tail -4 || true; }
done
echo "  (D01 reference at batch 64 was 12.8 min/epoch)"

echo "=== E. DEAD JOBS: DO THEY HOLD ANYTHING? ==="
for J in 202229 202293 202294 202315 202507 215429; do
  s=$(squeue -j "$J" -h -o "%i %t %C %b %R" 2>/dev/null)
  [ -n "$s" ] && echo "  $s" || echo "  $J not in queue"
done
echo "  (PD jobs reserve nothing; only R jobs hold resources)"

echo "=== F. NODES I AM ON: HOW MUCH IS FREE BESIDE ME ==="
for N in ngu001 ngu003 ngu004 ngu005 ngu011; do
  scontrol show node "$N" 2>/dev/null | tr ' ' '\n' | grep -E '^(NodeName|CPUAlloc|CPUTot|AllocTRES|CfgTRES|State)=' | tr '\n' ' '; echo
done
echo ID33_UTILISATION_SEQ7_COMPLETE
