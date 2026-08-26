#!/bin/bash
set -o pipefail
OUT=/data1/home/sunyiq/hpc_mailbox/outbox
echo "=== PROBE LOGS ==="
for j in 212909 212910 212911; do
  echo "  ================ job $j ================"
  if [ -f "$OUT/nodetest_${j}.out" ]; then sed -n '1,40p' "$OUT/nodetest_${j}.out" | sed 's/^/    /'; else echo "    (stdout missing)"; fi
  if [ -s "$OUT/nodetest_${j}.err" ]; then echo "    -- stderr --"; sed -n '1,10p' "$OUT/nodetest_${j}.err" | sed 's/^/      /'; fi
done
echo "=== CURRENT hgpu8 STATE ==="
sinfo -p hgpu8 -o "%.10P %.6a %.10N %.10T %.5c %.10G" 2>&1 || true
echo "=== DONE ==="
