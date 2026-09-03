#!/bin/bash
# seq=441 部署成对重训脚本(含四处过期指向修复)并提交冻结的 0-1 串行两臂
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
MB=$HOME/hpc_mailbox
SRC=$(ls -d "$MB"/*/inbox/id29-nearing2022-da/payload 2>/dev/null | head -1)
[ -z "$SRC" ] && SRC="$MB/inbox/id29-nearing2022-da/payload"
echo "payload dir: $SRC"
ls -la "$SRC" 2>/dev/null || { echo "PAYLOAD NOT FOUND"; exit 1; }

echo "=== 1. 安装四个文件 ==="
install -m 755 "$SRC/run_warmup_target_pair.slurm"     "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm"
install -m 755 "$SRC/analyze_warmup_target_pair.slurm" "$ROOT/src/29_nearing2022_da_ar/hpc/analyze_warmup_target_pair.slurm"
install -m 644 "$SRC/prepare_warmup_target_pair.py"    "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py"
install -m 644 "$SRC/analyze_warmup_target_pair.py"    "$ROOT/src/29_nearing2022_da_ar/scripts/analyze_warmup_target_pair.py"

echo "=== 2. 散列必须逐一自证 ==="
FAIL=0
check() { A=$(sha256sum "$1" | awk '{print $1}'); [ "$A" = "$2" ] && echo "OK   $(basename $1)" || { echo "MISMATCH $(basename $1) got=$A want=$2"; FAIL=1; }; }
check "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm"     fa47f0318bd2d38e337177a70ccfbef7c536ea62a71c5773a9ec29aabe46e44e
check "$ROOT/src/29_nearing2022_da_ar/hpc/analyze_warmup_target_pair.slurm" 75a853981b933e3fb71fc765e5faa7503ac2cfb8da90d7b071056ff95f2cc691
check "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 31f856df60b0daacea873386880581f975480c842fae0d605a5abe4b40a1b664
check "$ROOT/src/29_nearing2022_da_ar/scripts/analyze_warmup_target_pair.py" 6ea424e02be947cf0823728c437ea7710fa68dc7cee2ac23304e2999e45135a4
check "$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_target_paired_analysis_contract.json" 5bb3da898bba8b01b290a2a3efe70a943235fd103e9913711d19a6290869a114
check "$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_target_paired_retraining_protocol.json" 16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1
[ "$FAIL" = "0" ] || { echo "ABORT: 散列不符, 不提交"; exit 1; }
bash -n "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm" && echo "syntax OK"

echo "=== 3. 幂等保护 + 提交冻结的两臂(串行) ==="
EXIST=$(squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c 'N22-warmpair' || true)
echo "existing N22-warmpair: $EXIST"
[ -e "$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair" ] && { echo "ABORT: warmup_pair 已存在"; exit 1; }
if [ "$EXIST" = "0" ]; then
  cd "$ROOT"
  sbatch --job-name=N22-warmpair src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm
else
  echo "已在队列, 跳过提交"
fi
echo "=== 4. 队列 ==="
squeue -u sunyiq -h -o '%.12i %.16j %.10T %.11L %R' 2>/dev/null | grep -E 'N22' || echo none
