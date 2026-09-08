set -o pipefail
L=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs
for F in N22-warmpair_219423_0.err N22-warmpair_219423_0.out N22-warmpair_219423_1.err; do
  echo "=== $F (tail 40) ==="
  tail -40 "$L/$F" 2>/dev/null || echo "  unreadable"
done
echo "=== replv2 220487 logs ==="
find /data1/home/sunyiq/nearing2022_da -maxdepth 4 -name '*220487*' 2>/dev/null | head -5
