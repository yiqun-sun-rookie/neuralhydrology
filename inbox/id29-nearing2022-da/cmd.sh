set -o pipefail
L=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs
for f in N22-warmpair_219423_0.err N22-warmpair_219423_0.out N22-warmpair_219423_1.err; do
  echo "=== $f (tail 40) ==="
  tail -40 "$L/$f" 2>/dev/null || echo missing
done
