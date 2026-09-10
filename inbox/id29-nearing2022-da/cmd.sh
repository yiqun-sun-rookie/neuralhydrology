set -o pipefail
L=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs
echo "=== 219423_0.err (tail 40) ==="
tail -40 "$L/N22-warmpair_219423_0.err" 2>/dev/null || echo '  no err'
echo "=== 219423_0.out (tail 25) ==="
tail -25 "$L/N22-warmpair_219423_0.out" 2>/dev/null || echo '  no out'
echo "=== 219423_1.err (tail 25) ==="
tail -25 "$L/N22-warmpair_219423_1.err" 2>/dev/null || echo '  no err'
exit 0
