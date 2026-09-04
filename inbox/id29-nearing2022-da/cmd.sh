set -o pipefail
L=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs
for F in N22-warmpair_219423_0.err N22-warmpair_219423_0.out N22-warmpair_219423_1.err; do
  echo "=== $F (tail 40) ==="
  tail -40 "$L/$F" 2>/dev/null || echo "  missing"
done
echo "=== 220487 replv2 log ==="
ls -1t $L/*repl* 2>/dev/null | head -5 || true
for F in $(ls -1t $L/*220487* 2>/dev/null | head -2); do echo "--- $F"; tail -30 "$F" 2>/dev/null || true; done
