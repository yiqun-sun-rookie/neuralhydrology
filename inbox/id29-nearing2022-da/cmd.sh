set -o pipefail
L=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs
for T in 0 1; do
  echo "===== 219423_$T ERR ====="; tail -30 "$L/N22-warmpair_219423_$T.err" || true
  echo "===== 219423_$T OUT ====="; tail -30 "$L/N22-warmpair_219423_$T.out" || true
done
exit 0
