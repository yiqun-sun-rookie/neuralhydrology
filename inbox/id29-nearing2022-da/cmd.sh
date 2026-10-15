set -o pipefail
# READ-ONLY (seq 739): real training speed
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== current job ==="
sacct -X -n -P -j 242758 --format=JobID,State,Elapsed,NodeList
L="$ROOT/closure_20260810/logs/N22-warmpair2_242758_0.out"
grep -aoE "Epoch [0-9]+ .{0,160}" "$L" | tail -4
tail -c 400 "$L" | tr '\r' '\n' | tail -2
echo "=== earlier registered 30-epoch training jobs (elapsed) ==="
sacct -X -n -P -S 2026-08-01 --format=JobID,JobName,State,Elapsed,NodeList 2>/dev/null | grep -E 'N22' | grep -E 'COMPLETED' | grep -iE 'train|ar|DA|sim' | head -12
exit 0
