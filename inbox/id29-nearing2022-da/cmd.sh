set -o pipefail
cd /data1/home/sunyiq/nearing2022_da/closure_20260810/logs
for F in N22-warmpair_219423_0.err N22-warmpair_219423_0.out; do
  echo "=== $F (tail 40) ==="
  tail -40 "$F" 2>/dev/null || echo '  unreadable'
done
