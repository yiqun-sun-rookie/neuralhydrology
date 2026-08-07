#!/bin/bash
# a02b seq=2 : why do 4 COMPLETED jobs have only 1 tarball?
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02
MB=/data1/home/$USER/hpc_mailbox/outbox

echo "=== A TAIL OF THE 4 COMPLETED LOGS ==="
for j in a02_pre_s43-201683 a02_pre_s45-201687 a02_sam_s45-201688 a02_pre_s46-201689; do
  echo "--- $j.out (last 14 lines) ---"
  timeout 15 tail -14 "$PKG/logs/$j.out" 2>&1 | sed 's/^/   /'
  if [ -s "$PKG/logs/$j.err" ]; then
    echo "   -- .err tail --"; timeout 15 tail -6 "$PKG/logs/$j.err" 2>&1 | sed 's/^/   /'
  fi
done

echo "=== B OUTPUT DIRS ==="
timeout 25 ls -d $PKG/models/*/ 2>&1 | sed 's/^/  /'
echo "--- contents of each ---"
timeout 30 bash -c 'for d in '"$PKG"'/models/*/; do printf "  %-34s %s files, best=%s\n" "$(basename $d)" "$(ls $d 2>/dev/null | wc -l)" "$(ls $d 2>/dev/null | grep -c best)"; done' 2>&1

echo "=== C ALL TARBALLS AND STAGING ==="
timeout 20 ls -la $MB/ 2>&1 | grep -E "a02|total" | sed 's/^/  /'
timeout 20 ls -la $PKG/*.tar.gz $PKG/results* 2>&1 | sed 's/^/  /' | head -20

echo "=== D SLURM SCRIPT TAIL (how the tarball is made) ==="
timeout 15 ls $PKG/slurm/ 2>&1 | head -14 | sed 's/^/  /'
timeout 15 tail -22 "$PKG/slurm/a02_pre_s43.slurm" 2>&1 | sed 's/^/  /'
