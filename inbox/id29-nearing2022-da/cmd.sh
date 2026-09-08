set -o pipefail
L=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs
for F in N22-warmpair_219423_0.err N22-warmpair_219423_0.out N22-warmpair_219423_1.err; do
  echo "=== $F ($(stat -c %s $L/$F 2>/dev/null) bytes) ==="
  tail -n 40 "$L/$F" 2>/dev/null || true
done
echo "=== replv2 logs ==="
ls -1t $L 2>/dev/null | grep -i repl | head -6 || echo none
for F in $(ls -1t $L 2>/dev/null | grep -i repl | head -2); do echo "--- $F ---"; tail -n 25 "$L/$F" 2>/dev/null || true; done
exit 0
