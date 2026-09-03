set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for T in 0 1; do
  echo "===== TASK $T ====="
  F=$(ls -1 $ROOT/logs/29_nearing2022_da_ar/*219423_$T* 2>/dev/null; ls -1 $ROOT/logs/**/*219423_$T* 2>/dev/null) || true
  echo "files: $F"
  for f in $F; do echo "--- $f"; tail -40 "$f" || true; done
done
echo "===== FIND ANY 219423 LOGS ====="
find $ROOT/logs -name '*219423*' -newermt '2026-09-01' 2>/dev/null | head -20 || true
exit 0
