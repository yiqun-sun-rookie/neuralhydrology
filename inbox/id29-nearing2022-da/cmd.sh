set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for T in 0 1; do
  echo "===== TASK $T ====="
  for P in $(scontrol show job 219423_$T 2>/dev/null | tr ' ' '\n' | sed -n -e 's/^StdErr=//p' -e 's/^StdOut=//p' | sort -u); do
    echo "--- $P ---"; [ -f "$P" ] && tail -40 "$P" || echo "(no file)"
  done
done
echo "===== LOG DIR SEARCH ====="
find "$ROOT" -maxdepth 4 -name '*219423*' -newermt '2026-09-02' 2>/dev/null | head -20 || true
echo "===== FALLBACK TAILS ====="
for F in $(find "$ROOT" -maxdepth 4 -name '*219423*' 2>/dev/null | head -6); do echo "--- $F ---"; tail -40 "$F" || true; done
exit 0
