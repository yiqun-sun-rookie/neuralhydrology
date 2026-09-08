#!/bin/bash
# forcing-swap seq=14 -- ship scripts_public_median.py into the landing dir (seq=13 could not find it at the
# attr-swap landing; without it every arm would fail on its last step). Also report gate/arm status.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/forcing_swap_daily_2026_09
M=$HOME/hpc_mailbox/inbox/attrswap-daily/payload
echo "=== A. INSTALL ==="
cp "$M/scripts_public_median.py" "$R/scripts_public_median.py" || { echo COPY_FAILED; exit 1; }
sed -i 's/\r$//' "$R/scripts_public_median.py"
echo "installed: $(sha256sum $R/scripts_public_median.py | cut -c1-16)  $(wc -l < $R/scripts_public_median.py) lines"
cat "$R/scripts_public_median.py"
echo "=== B. WHERE THE ATTR-SWAP COPY ACTUALLY LIVES (for the record) ==="
find /data1/home/sunyiq/attr_swap_daily_2026_09 -maxdepth 2 -name "scripts_public_median.py" 2>/dev/null || echo "  (not found there)"
echo "=== C. SANITY: it imports and finds the holdout list from the landing dir ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
cd "$R" && python -u -c "
import pathlib
src = pathlib.Path('scripts_public_median.py').read_text()
compile(src, 'scripts_public_median.py', 'exec')
print('compiles OK; holdout list present:', pathlib.Path('basin_lists/holdout_107.txt').exists())
"
echo "=== D. QUEUE ==="
squeue -u "$USER" -o '%.11i %.22j %.9T %.10M %.9N %.22E' 2>&1 | grep -Ei 'fswap|JOBID' || echo '  (none queued)'
sacct -j 223868 -X --format=JobID%9,JobName%14,State%12,ExitCode%8,Elapsed%10,NodeList%9 2>&1
echo "=== E. GATE LOG SO FAR ==="
f=$(ls -t "$R"/logs/slurm_fswap_gate_*.out 2>/dev/null | head -1) || true
if [ -n "$f" ]; then echo "--- $(basename $f) ($(stat -c%s $f) bytes) ---"; tail -20 "$f"; else echo "  (gate not started yet)"; fi
echo "=== DONE ==="
