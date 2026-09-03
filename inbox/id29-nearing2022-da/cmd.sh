#!/bin/bash
# seq=436 只读: 成对重训脚本的准入检查能否通过
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
echo "=== A. 脚本校验的两个合同文件 ==="
for f in "$D/warmup_target_paired_retraining_protocol.json" "$D/warmup_target_paired_analysis_contract.json"; do
  [ -f "$f" ] && sha256sum "$f" || echo "MISSING $f"
done
echo "期望 PROTOCOL=16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1"
echo "期望 ANALYSIS=5bb3da898bba8b01b290a2a3efe70a943235fd103e9913711d19a6290869a114"
echo "=== B. 审计目录 (脚本指向 _all531, 入口门实际是 _all531_v2) ==="
ls -d "$D"/author_v13_* 2>/dev/null || echo "  none"
echo "=== C. 脚本硬编码的入口门作业 202506/202507 实际状态 ==="
sacct -X -n -P -j 202506,202507 --format=JobID,JobName,State,ExitCode 2>/dev/null || echo none
echo "=== D. 实际满足入口门的 202510/202511 ==="
sacct -X -n -P -j 202510,202511 --format=JobID,JobName,State,ExitCode 2>/dev/null || echo none
echo "=== E. MAIN_JOBS 失败守卫会捕获什么 (非空即阻断) ==="
sacct -n -P -j 202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315 --format=JobIDRaw,State,ExitCode 2>/dev/null | awk -F'|' '$1 !~ /\./ && $2 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/' || true
echo "--- end of guard output ---"
echo "=== F. 成对重训产物目录是否已存在 ==="
ls -d "$D/warmup_pair" 2>/dev/null && ls -la "$D/warmup_pair" 2>/dev/null || echo "  warmup_pair 不存在(干净)"
echo "=== G. 脚本与准备脚本的服务器侧指纹 ==="
sha256sum "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm" "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 2>/dev/null || true
