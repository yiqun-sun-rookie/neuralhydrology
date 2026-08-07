#!/bin/bash
# id05-adversarial seq=26: read-only survey of the l1l2 record dirs before re-running the
# l2-signature and drought analyses on all 531 basins.
export LC_ALL=C
A=/data1/home/$USER/adv531
R=$A/results/05_adversarial_robustness

echo "=== TIME ==="
date

echo "=== CANDIDATE RECORD DIRS ==="
for d in $R/id18_s100/l1l2_records $R/id18_s100_hpc/l1l2_531/l1l2_records $R/id18_s100_merged/l1l2_records; do
  if [ -d "$d" ]; then
    echo "$d : $(ls -1 $d/*.npz 2>/dev/null | wc -l) npz, $(du -sh $d 2>/dev/null | cut -f1)"
    [ -L "$d" ] && echo "    (symlink -> $(readlink -f $d))"
  else
    echo "$d : ABSENT"
  fi
done

echo "=== ANY OTHER l1l2_records UNDER adv531 ==="
find $R -maxdepth 4 -type d -name "l1l2_records" 2>/dev/null | head -10

echo "=== STAGED SUMMARY FILES ==="
for f in l1_attribution_summary.csv l2_signatures_summary.csv hydro_vulnerability_summary.csv; do
  printf "  %-36s %s rows\n" "$f" "$(($(wc -l < $R/id18_s100/$f 2>/dev/null || echo 1) - 1))"
done

echo "=== EXACT-MOMENT JOB ==="
sacct -j 201707 -X --format=JobID%14,State%12,ExitCode%8,Elapsed%10 2>&1 | head -8
