set -o pipefail
L=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs
for F in N22-warmpair_219423_0.err N22-warmpair_219423_0.out N22-warmpair_219423_1.err; do
  echo "==== $F ===="
  tail -40 "$L/$F" 2>/dev/null || echo "  unreadable"
done
echo "==== replv2 220487 ===="
ls -1 "$L" 2>/dev/null | grep 220487 || echo none
for F in $(ls -1 "$L" 2>/dev/null | grep 220487); do echo "---- $F"; tail -25 "$L/$F" 2>/dev/null || true; done
exit 0
