set -o pipefail
L=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs
for T in 0 1; do
  echo "=== ERR $T ==="; tail -30 "$L/N22-warmpair_219423_$T.err" 2>/dev/null || true
  echo "=== OUT $T ==="; tail -30 "$L/N22-warmpair_219423_$T.out" 2>/dev/null || true
done
exit 0
