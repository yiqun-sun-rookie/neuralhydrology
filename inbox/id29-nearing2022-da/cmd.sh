set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
L="$ROOT/closure_20260810/logs"
date --iso-8601=seconds
for J in N22-warmpair_219423_0 N22-warmpair_219423_1; do
  for E in err out; do echo "--- $J.$E"; [ -f "$L/$J.$E" ] && tail -n 30 "$L/$J.$E" || echo "  (no file)"; done
done
echo "--- replv2 220487"
ls "$L" 2>/dev/null | grep 220487 || true
for F in $(ls "$L" 2>/dev/null | grep 220487); do echo "--- $F"; tail -n 20 "$L/$F" || true; done
exit 0
