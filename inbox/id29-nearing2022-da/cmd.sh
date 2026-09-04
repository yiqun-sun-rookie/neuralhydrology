#!/bin/bash
# seq=456 只读且高优先: 服务器侧数据加载器是否被加入预热掩码, 及其相对 120 个评价的时间顺序
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
BD="$ROOT/neuralhydrology/datasetzoo/basedataset.py"
echo "=== A. 服务器侧 basedataset.py ==="
ls -la "$BD" 2>/dev/null || echo MISSING
sha256sum "$BD" 2>/dev/null || true
echo "旧交接登记(未加掩码)= 4658816ea3110a1c5c0982459dca4f7ac985beb983b12df0d 前16位 4658816ea3110a1c"
echo "本地当前(含掩码+anchornse)= 82552d7113c93556"
echo "=== B. 是否含那条掩码语句 ==="
grep -n "index < start_date" "$BD" 2>/dev/null || echo "  NOT PRESENT (未含掩码)"
echo "=== C. 是否含别的项目的 anchornse 功能 ==="
grep -c "anchornse\|_tercile_env" "$BD" 2>/dev/null || echo 0
echo "=== D. 时间顺序: 加载器 vs 120 个评价产物 ==="
stat -c '%y  %n' "$BD" 2>/dev/null || true
for c in N22-EVAL-TS-AR-L01-TR025-TE000-S0 N22-EVAL-TS-AR-L01-TR050-TE000-S0; do
  P="$ROOT/closure_20260810/evaluations/time_split/autoregression/$c/test/model_epoch030/test_results.p"
  [ -f "$P" ] && stat -c '%y  %n' "$P" || echo "  missing $c"
done
echo "--- 汇总与判定产物 ---"
for f in aggregation/evaluations/time_split_vs_author.csv aggregation/final_reproduction_gate.json; do
  P="$ROOT/closure_20260810/$f"; [ -f "$P" ] && stat -c '%y  %n' "$P" || echo "  missing $f"
done
echo "=== E. 早期已完成的评价(2026-08-10 那批 60 个之一)作对比 ==="
P="$ROOT/closure_20260810/evaluations/time_split/assimilation"
ls -1 "$P" 2>/dev/null | head -1 | while read d; do stat -c '%y  %n' "$P/$d/test/model_epoch030/test_results.p" 2>/dev/null || true; done
echo "=== F. 219423 两臂最终状态 ==="
sacct -j 219423 -X -n -P --format=JobID,State,ExitCode,Elapsed 2>/dev/null || echo none
