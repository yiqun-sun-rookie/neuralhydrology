#!/bin/bash
# a02b seq=3 : RESCUE tarballs out of the git-managed outbox, then report.
# NEVER read *.err (tqdm progress bars, hundreds of MB).
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02
MB=/data1/home/$USER/hpc_mailbox/outbox
SAFE=/data1/home/$USER/a02_results

echo "=== A RESCUE COPY (out of git working tree) ==="
mkdir -p "$SAFE"
timeout 120 bash -c 'cp -n '"$MB"'/a02_*.tar.gz '"$SAFE"'/ 2>/dev/null; true'
timeout 20 ls -la "$SAFE"/ 2>&1 | grep -E "a02|total" | sed 's/^/  /'

echo "=== B PER-RUN SUMMARY (from .out only) ==="
timeout 60 bash -c '
for f in '"$PKG"'/logs/a02_pre_s4*.out '"$PKG"'/logs/a02_sam_s4*.out; do
  [ -f "$f" ] || continue
  b=$(basename "$f" .out)
  best=$(grep -a "Best median NSE" "$f" 2>/dev/null | tail -1)
  pack=$(grep -a "a02_.*\.tar\.gz" "$f" 2>/dev/null | tail -1 | awk "{print \$5, \$9}")
  ep=$(grep -ac "^Epoch" "$f" 2>/dev/null)
  printf "  %-24s ep=%-3s %-42s pack=[%s]\n" "$b" "$ep" "${best:-<still running>}" "${pack:-none}"
done' 2>&1

echo "=== C MODEL OUTPUT DIRS (can we rebuild a lost tarball?) ==="
timeout 40 bash -c 'for d in '"$PKG"'/models/*/; do
  printf "  %-32s files=%-3s size=%s\n" "$(basename $d)" "$(ls -1 $d 2>/dev/null | wc -l)" "$(du -sh $d 2>/dev/null | cut -f1)"
done' 2>&1

echo "=== D WHAT THE PACKAGING STEP TARS ==="
timeout 15 grep -a -A8 "PACKAGING RESULT" "$PKG/slurm/a02_pre_s43.slurm" 2>&1 | sed 's/^/  /'

echo "=== E MAILBOX OUTBOX NOW ==="
timeout 20 ls -la "$MB"/a02_*.tar.gz 2>&1 | awk '{print "  ",$9,$5}'
