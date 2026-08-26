#!/bin/bash
# Resume the family: submit exactly the missing indices, on both 3090 partitions.
#
# Ten tasks of half one already completed cleanly on ngu008 before the earlier
# cancel, so the missing set in half one is the contiguous range 10..719 and in
# half two it is all of 0..719. The command line overrides the script's own
# --array, which is what makes a resume possible without editing the launcher.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. CANCEL MY REDUNDANT PROBES ==="
for j in 212915 212920; do
  st=$(sacct -j "$j" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
  echo "  $j ($st) -> cancel"
  scancel "$j" 2>&1 || true
done

echo "=== B. RECONFIRM THE MISSING SET ==="
cd "$ROOT/repo" || exit 1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"
python - <<'PYEOF'
import os, sys
sys.path.insert(0, "scripts/analysis"); sys.path.insert(0, "scripts/modeling")
import zhenjiang_oyv_n4_contract as c
root = "/data1/home/sunyiq/zhenjiang_oyv_v1/n4_tasks"
need = {"best_state.pt","training_history.csv","test_predictions.npz","run_identity.json","completion_manifest.json"}
missing = [i for i, t in enumerate(c.enumerate_tasks())
           if not (os.path.isdir(os.path.join(root, str(t["task_id"])))
                   and need <= set(os.listdir(os.path.join(root, str(t["task_id"])))))]
lo = [m for m in missing if m < 720]
hi = [m - 720 for m in missing if m >= 720]
def contiguous(v):
    return bool(v) and v == list(range(v[0], v[-1] + 1))
print("  missing total:", len(missing))
print("  half one local range:", (lo[0], lo[-1]) if lo else None, "contiguous:", contiguous(lo), "count:", len(lo))
print("  half two local range:", (hi[0], hi[-1]) if hi else None, "contiguous:", contiguous(hi), "count:", len(hi))
with open("/data1/home/sunyiq/zhenjiang_oyv_v1/resume_spec.txt", "w") as f:
    f.write("%s %s %s %s\n" % (
        ("%d-%d" % (lo[0], lo[-1])) if contiguous(lo) else "NONCONTIGUOUS",
        len(lo),
        ("%d-%d" % (hi[0], hi[-1])) if contiguous(hi) else "NONCONTIGUOUS",
        len(hi)))
PYEOF
read R1 N1 R2 N2 < "$ROOT/resume_spec.txt"
echo "  half one array spec: $R1 ($N1 tasks)"
echo "  half two array spec: $R2 ($N2 tasks)"
case "$R1$R2" in *NONCONTIGUOUS*) echo "  missing set is not contiguous; refusing to guess"; exit 1;; esac

echo "=== C. SUBMIT ==="
# Concurrency 8 per half, 16 in flight in total: the same footprint the finished
# family ran at, now spread over two partitions instead of one.
o1=$(sbatch --array="${R1}%8" --export=ALL,N4_INDEX_OFFSET=0 scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$o1"
A1=$(echo "$o1" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$A1" ] || { echo SUBMIT_FAILED_1; exit 1; }
o2=$(sbatch --array="${R2}%8" --export=ALL,N4_INDEX_OFFSET=720 scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$o2"
A2=$(echo "$o2" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$A2" ] || { echo "SUBMIT_FAILED_2, cancelling $A1"; scancel "$A1" 2>&1 || true; exit 1; }
echo "  half one = $A1   half two = $A2"

echo "=== D. TIDY MY OWN THROWAWAY ROOTS ==="
rm -rf "$ROOT/n4_smoke" "$ROOT"/equiv_scratch_* 2>/dev/null
echo "  smoke and equivalence scratch cleared"

echo "=== E. STATE ==="
sleep 30
squeue -u "$USER" -h -o "%.20i %.12j %.14P %.9T" 2>/dev/null | head -10 || true
echo "  running now : $(squeue -u "$USER" -h -t RUNNING -o '%i' 2>/dev/null | wc -l)"
echo "  n4_tasks now: $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l)"
echo "RESUME_HALF_1=$A1"
echo "RESUME_HALF_2=$A2"
echo "STATUS=RESUMED"
echo "=== DONE ==="
