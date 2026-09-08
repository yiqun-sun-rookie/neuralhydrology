set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== locate logs for 219423 / 220487 ==="
find "$ROOT/logs" -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -20 || true
echo "=== 219423_0 err tail ==="
F=$(find "$ROOT" -maxdepth 4 -name '*219423_0*.err' 2>/dev/null | head -1)
echo "file=$F"; [ -n "$F" ] && tail -40 "$F" || true
echo "=== 219423_1 err tail ==="
G=$(find "$ROOT" -maxdepth 4 -name '*219423_1*.err' 2>/dev/null | head -1)
echo "file=$G"; [ -n "$G" ] && tail -40 "$G" || true
echo "=== 220487 err tail ==="
H=$(find "$ROOT" -maxdepth 4 -name '*220487*.err' 2>/dev/null | head -1)
echo "file=$H"; [ -n "$H" ] && tail -40 "$H" || true
echo "=== 219423_0 out tail ==="
O=$(find "$ROOT" -maxdepth 4 -name '*219423_0*.out' 2>/dev/null | head -1)
echo "file=$O"; [ -n "$O" ] && tail -30 "$O" || true
exit 0
