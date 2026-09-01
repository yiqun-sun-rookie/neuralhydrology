#!/bin/bash
# nature1st-attr-swap seq=116 -- READ-ONLY. armC baseline replicates (216687/216688).
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
cd "$RUN" || { echo RUN_DIR_MISSING; exit 1; }
date "+wallclock %F %T %z"

echo "=== A. STATE ==="
squeue -u $USER -o '%.11i %.26j %.9T %.10M %.9N %.9P' 2>&1 | grep -Ei 'armC|armJ|JOBID' || echo '  (none queued)'
sacct -j 216687,216688 -X --format=JobID%10,JobName%24,State%12,ExitCode%8,Elapsed%11,NodeList%9 2>&1

echo "=== B. LOGS ==="
for spec in '216687:s43' '216688:s44'; do
  J=${spec%%:*}; S=${spec##*:}
  f=logs/attr_swap/armC_us_minus_net_${S}-${J}.out
  echo "--- armC $S (job $J) ---"
  if [ ! -f "$f" ]; then echo "  (no log)"; continue; fi
  echo "  bytes=$(stat -c%s "$f")  mtime=$(stat -c%y "$f" | cut -c1-19)"
  grep -E "\[guard\]" "$f" 2>/dev/null | head -2 || true
  grep -E "PyTorch .*CUDA" "$f" 2>/dev/null | head -1 || true
  grep -E "RuntimeError|Traceback|CUDA error|FATAL|Killed|out of memory" "$f" 2>/dev/null | head -4 || echo "  errors: none"
  grep -E "^Epoch|Best val median NSE|Done\." "$f" 2>/dev/null | tail -5 || true
done

echo "=== C. RESULTS SO FAR ==="
for S in 42 43 44; do
  d=models/q_lstm_usminus4_hpc_s${S}
  if [ -f $d/best_metrics.json ]; then
    dn=$(ls $d/eval_val_per_station.csv 2>/dev/null | wc -l)
    python -c "import json,sys;m=json.load(open(sys.argv[1]));print(f'  armC s${S}: median={m[\"median_nse\"]:.4f} epoch={m[\"epoch\"]} perstation_csv=${dn}')" $d/best_metrics.json 2>&1
  else echo "  armC s${S}: absent"; fi
done

echo "=== D. PAIRED: armC SEED SPREAD (the whole point) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - <<'PY' 2>&1
import os, itertools
import numpy as np, pandas as pd
R='/data1/home/sunyiq/nature_1st/models'
def load(d):
    p=os.path.join(R,d,'eval_val_per_station.csv')
    return pd.read_csv(p).set_index('station') if os.path.exists(p) else None
C={s:load(f'q_lstm_usminus4_hpc_s{s}') for s in (42,43,44)}
have=[s for s in (42,43,44) if C[s] is not None]
print('armC seeds with per-station scores:', have)
for s in have: print(f'  armC s{s}: median={C[s].nse.median():.4f}')
rng=np.random.default_rng(0)
def paired(A,B,la,lb):
    j=B[['nse','stratum']].join(A[['nse']],lsuffix='_b',rsuffix='_a').dropna(subset=['nse_b','nse_a'])
    d=(j.nse_b-j.nse_a).values
    bs=[np.median(rng.choice(d,len(d),replace=True)) for _ in range(5000)]
    print(f'  [{lb} vs {la}] paired_med={np.median(d):+.4f} 95%CI [{np.percentile(bs,2.5):+.4f},{np.percentile(bs,97.5):+.4f}]  drop>0.10={(d<-0.10).mean()*100:.1f}%')
if len(have)>=2:
    print('--- armC seed-vs-seed (this IS the baseline noise) ---')
    for x,y in itertools.combinations(have,2): paired(C[x],C[y],f'armC_s{x}',f'armC_s{y}')
print('--- armJ seeds vs EACH armC seed ---')
J={s:load(f'q_lstm_armJ_hpc_s{s}') for s in (42,43,44)}
for cs in have:
    for js in (42,43,44):
        if J[js] is not None: paired(C[cs],J[js],f'armC_s{cs}',f'armJ_s{js}')
PY
echo "=== END seq=116 ==="
