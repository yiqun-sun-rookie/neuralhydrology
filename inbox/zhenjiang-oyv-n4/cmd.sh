#!/bin/bash
# Independent audit, structural checks first (no graphics processor needed).
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
cd "$ROOT/repo" || exit 1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"
echo "  audit script: $(sha256sum scripts/analysis/independent_audit_zhenjiang_oyv_n4.py | cut -d' ' -f1)"
rm -rf "$ROOT/n4_audit_structural"
python -u scripts/analysis/independent_audit_zhenjiang_oyv_n4.py \
  --task-root "$ROOT/n4_tasks" \
  --impact-root "$ROOT/n4_impact" \
  --output-root "$ROOT/n4_audit_structural" 2>&1 | tail -30
echo "=== MISMATCH SAMPLE ==="
head -8 "$ROOT/n4_audit_structural/audit_mismatches.csv" 2>/dev/null | sed 's/^/  /'
echo "=== COST COMPARISON SAMPLE ==="
head -6 "$ROOT/n4_audit_structural/audit_cost_comparison.csv" 2>/dev/null | sed 's/^/  /'
echo "=== DONE ==="
