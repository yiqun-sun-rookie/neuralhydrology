#!/bin/bash
# nature1st-attr-swap seq=68 -- armG watchdog. READ-ONLY, no sbatch, no resubmit.
# Job 207826 = q_armG_china_supplyable, submitted 2026-08-21 17:05, 40-epoch cap.
# Reference wall time: armE 3h02 (12 epochs), armF 6h06 (25 epochs).
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
J=207826
cd "$RUN" || { echo RUN_DIR_MISSING; exit 1; }

echo "=== A. STATE ==="
squeue -j $J -o '%.10i %.28j %.10T %.10M %.24R' 2>&1
sacct -j $J -X --format=JobID%10,JobName%26,State%12,ExitCode%8,Elapsed%12,NodeList%9 2>&1

echo "=== B. GUARD FIRED? (would mean the attribute swap did not take) ==="
f=$(ls logs/attr_swap/armG_china_supplyable-${J}.out 2>/dev/null | head -1)
e=$(ls logs/attr_swap/armG_china_supplyable-${J}.err 2>/dev/null | head -1)
if [ -z "$f" ]; then echo "(no stdout log yet -- still pending)"; else
  grep -E "\[guard\]|attributes, .* stations in meta" "$f" 2>/dev/null | head -4 || true
  grep -E "RuntimeError|Traceback|CUDA|FATAL|refusing" "$f" "$e" 2>/dev/null | head -8 || true
fi

echo "=== C. PROGRESS ==="
if [ -n "$f" ]; then
  echo "log bytes: $(stat -c%s "$f")  last touched: $(stat -c%y "$f" | cut -c1-19)"
  grep -E "^Epoch|Best val median NSE|Done\." "$f" 2>/dev/null | tail -8 || true
fi

echo "=== D. FINISHED? ==="
if [ -f models/q_lstm_armG_hpc_s42/best_metrics.json ]; then
  cat models/q_lstm_armG_hpc_s42/best_metrics.json 2>&1
else echo '(best_metrics.json not written yet)'; fi

echo "=== E. PAIRED VERDICT (only runs once eval_val_per_station.csv exists) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - <<'PY' 2>&1
import os
import numpy as np, pandas as pd
R='/data1/home/sunyiq/nature_1st/models'
P={'control':'q_lstm_control_hpc_s42','global':'q_lstm_hydroatlas_hpc_s42',
   'armC':'q_lstm_usminus4_hpc_s42','armF':'q_lstm_armF_hpc_s42',
   'armG':'q_lstm_armG_hpc_s42'}
def load(k):
    p=os.path.join(R,P[k],'eval_val_per_station.csv')
    return pd.read_csv(p).set_index('station') if os.path.exists(p) else None
if load('armG') is None:
    print('armG per-station scores not written yet -- nothing to judge')
else:
    def paired(la,lb,note):
        A,B=load(la),load(lb)
        j=B[['nse','stratum']].join(A[['nse']],lsuffix='_b',rsuffix='_a').dropna(subset=['nse_b','nse_a'])
        d=(j.nse_b-j.nse_a).values
        rng=np.random.default_rng(0)
        bs=[np.median(rng.choice(d,len(d),replace=True)) for _ in range(5000)]
        print(f'[{lb} vs {la}]  {note}')
        print(f'  n={len(j)}  {la} median {j.nse_a.median():.4f}   {lb} median {j.nse_b.median():.4f}')
        print(f'  group median diff   {j.nse_b.median()-j.nse_a.median():+.4f}')
        print(f'  PAIRED median diff  {np.median(d):+.4f}   95%CI [{np.percentile(bs,2.5):+.4f}, {np.percentile(bs,97.5):+.4f}]')
        print(f'  worse/better {(d<0).sum()}/{(d>0).sum()}   lost>0.10 {(d<-0.10).mean()*100:.1f}%  gained>0.10 {(d>0.10).mean()*100:.1f}%')
        for s,g in j.groupby('stratum'):
            print(f'    {s:<12} n={len(g):>3}  paired {np.median((g.nse_b-g.nse_a).values):+.4f}')
    paired('armC','armG','PRE-REGISTERED: pass >= -0.010 AND lost>0.10 <= 20%; reject < -0.030 OR > 35%')
    paired('armF','armG','China-supplyable substitutes vs the US-sourced four')
    paired('control','armG','context: vs the 12 US-proprietary attributes')
PY
echo "=== END seq=68 ==="
