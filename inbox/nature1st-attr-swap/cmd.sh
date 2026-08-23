#!/bin/bash
# read-only watchdog for armG (job 207826) -- NO sbatch, NO compute
set -o pipefail

RUN=/data1/home/sunyiq/nature_1st
J=207826
MD=$RUN/models/q_lstm_armG_hpc_s42

echo "=== A. STATE ==="
echo "wallclock now: $(date '+%F %T %z')"
squeue -j $J -o '%.10i %.28j %.10T %.10M %.24R' 2>&1 | head -5 || true
sacct -j $J -X --format=JobID%10,JobName%26,State%12,ExitCode%8,Elapsed%12,NodeList%9 2>&1 | head -5 || true

echo "=== B. GUARD (must say 17 attributes) ==="
grep '\[guard\]' $RUN/logs/attr_swap/armG_china_supplyable-$J.out 2>/dev/null | head -6 || true

echo "=== B2. ERRORS ==="
for f in $RUN/logs/attr_swap/armG_china_supplyable-$J.out $RUN/logs/attr_swap/armG_china_supplyable-$J.err; do
  echo "-- $f --"
  grep -E 'RuntimeError|Traceback|CUDA|FATAL|refusing' "$f" 2>/dev/null | head -12 || true
done

echo "=== C. PROGRESS ==="
OUT=$RUN/logs/attr_swap/armG_china_supplyable-$J.out
echo "out log bytes: $(stat -c%s $OUT 2>/dev/null)  last touched: $(stat -c%y $OUT 2>/dev/null)"
grep -E '^Epoch|Best val median NSE|Done\.' $OUT 2>/dev/null | tail -8 || true

echo "=== D. FINISHED? ==="
if [ -f $MD/best_metrics.json ]; then cat $MD/best_metrics.json | head -20 || true; else echo "-- best_metrics.json absent --"; fi
echo "-- artifact timestamps --"
for f in $MD/best_metrics.json $MD/eval_val_per_station.csv; do
  [ -f "$f" ] && echo "$(stat -c'%y  %s bytes' $f)  $f" || echo "absent: $f"
done

echo "=== E. PAIRED VERDICT ==="
if [ -f $MD/eval_val_per_station.csv ]; then
  source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
  conda activate nh_final
  python - <<'PY' 2>&1 | head -120
import os
import numpy as np, pandas as pd
R="/data1/home/sunyiq/nature_1st/models"
ARMS={"armG":"q_lstm_armG_hpc_s42","armC":"q_lstm_usminus4_hpc_s42",
      "armF":"q_lstm_armF_hpc_s42","control":"q_lstm_control_hpc_s42"}
D={}
for k,d in ARMS.items():
    p=os.path.join(R,d,"eval_val_per_station.csv")
    if not os.path.exists(p):
        print("MISSING:",k,p); continue
    df=pd.read_csv(p)
    D[k]=df
    print(f"{k:8s} rows={len(df)}  median={df['nse'].median():.4f}")
def boot(d,n=5000):
    rng=np.random.default_rng(0); a=np.asarray(d)
    m=[np.median(a[rng.integers(0,len(a),len(a))]) for _ in range(n)]
    return np.percentile(m,2.5), np.percentile(m,97.5)
res={}
for other in ["armC","armF","control"]:
    if "armG" not in D or other not in D: continue
    m=D["armG"].merge(D[other],on="station",suffixes=("_g","_o"))
    d=(m["nse_g"]-m["nse_o"]).values
    pmd=float(np.median(d)); lo,hi=boot(d)
    drop=float((d<-0.10).mean()); gain=float((d>0.10).mean())
    res[other]=(pmd,drop)
    print(f"\n---------- armG vs {other} ----------")
    print(f"paired n            = {len(d)}")
    print(f"median armG         = {D['armG']['nse'].median():.4f}")
    print(f"median {other:12s}= {D[other]['nse'].median():.4f}")
    print(f"group median diff   = {D['armG']['nse'].median()-D[other]['nse'].median():+.4f}")
    print(f"PAIRED median diff  = {pmd:+.4f}   95% CI [{lo:+.4f}, {hi:+.4f}]")
    print(f"worse / better      = {int((d<0).sum())} / {int((d>0).sum())}")
    print(f"frac drop > 0.10    = {drop*100:.1f}%")
    print(f"frac gain > 0.10    = {gain*100:.1f}%")
    sc = "stratum_g" if "stratum_g" in m.columns else ("stratum" if "stratum" in m.columns else None)
    if sc:
        print("by stratum (paired median diff, n):")
        for s,g in m.groupby(sc):
            dd=(g["nse_g"]-g["nse_o"]).values
            print(f"   {str(s):20s} {np.median(dd):+.4f}  n={len(dd)}")
if "armC" in res:
    pmd,drop=res["armC"]
    print("\n---------- PRE-REGISTERED DECISION vs armC ----------")
    print(f"paired median diff = {pmd:+.4f}   frac drop>0.10 = {drop*100:.1f}%")
    suf = (pmd>=-0.010) and (drop<=0.20)
    veto= (pmd< -0.030) or (drop>0.35)
    print(f"  rule SUFFICIENT : pmd >= -0.010 AND drop <= 20%  -> {suf}")
    print(f"  rule VETO       : pmd <  -0.030 OR  drop >  35%  -> {veto}")
    print("VERDICT:", "SUFFICIENT" if suf else ("VETO" if veto else "INCONCLUSIVE -- needs seeds 43/44, no single-seed conclusion allowed"))
PY
else
  echo "-- eval_val_per_station.csv absent, skip paired analysis --"
fi

echo "=== F. SEED 43/44 FOLLOW-UP PRESENT? ==="
for s in 43 44; do
  d=$RUN/models/q_lstm_armG_hpc_s$s
  if [ -d "$d" ]; then echo "-- $d EXISTS --"; ls -la "$d" 2>/dev/null | head -8 || true
  else echo "-- models/q_lstm_armG_hpc_s$s absent --"; fi
done
squeue -u sunyiq -o '%.10i %.28j %.9T %.10M %.20R' 2>&1 | grep -iE 'armG|JOBID' | head -10 || true

echo "=== END seq=87 ==="
