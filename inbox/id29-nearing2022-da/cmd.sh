set -o pipefail
L=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs
for F in N22-warmpair_219423_0.err N22-warmpair_219423_0.out N22-warmpair_219423_1.err; do
  echo "=== $F ($(stat -c %s "$L/$F" 2>/dev/null) bytes) ==="
  tail -40 "$L/$F" 2>/dev/null || true
done
echo "=== replv2 logs ==="
ls -t "$L" 2>/dev/null | grep -i 'replv2' | head -5 || echo none
for F in $(ls -t "$L" 2>/dev/null | grep -i 'replv2' | head -2); do echo "--- $F"; tail -30 "$L/$F" 2>/dev/null || true; done
exit 0
