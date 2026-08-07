#!/bin/bash
# id05-adversarial seq=30: exact-moment counterfactual status; merge parts if all five finished.
export LC_ALL=C
A=/data1/home/$USER/adv531
R=$A/results/05_adversarial_robustness/id18_s100
M=/data1/home/$USER/hpc_mailbox

echo "=== TIME ==="; date
echo "=== JOB 201707 ==="
sacct -j 201707 -X --format=JobID%14,State%12,ExitCode%8,Elapsed%10 2>&1 | head -8

echo "=== CHUNK PROGRESS ==="
for i in 0 1 2 3 4; do
  echo -n "  chunk $i: "; grep -E "^\[[0-9]+/|^DONE" $A/logs/adv531_exact_201707_${i}.out 2>/dev/null | tail -1
done

echo "=== PARTS ==="
ls -l $R/exact_moment_probe_eps0.1_part*.csv 2>&1 | awk '{print "  ", $5, $9}'
NP=$(ls -1 $R/exact_moment_probe_eps0.1_part*.csv 2>/dev/null | wc -l)
echo "  parts written: $NP / 5"

if [ "${NP:-0}" -eq 5 ]; then
  echo "=== MERGE + SUMMARY ==="
  cd $A
  python - <<'PY'
import glob, pandas as pd, numpy as np
R = "/data1/home/sunyiq/adv531/results/05_adversarial_robustness/id18_s100"
fs = sorted(glob.glob(f"{R}/exact_moment_probe_eps0.1_part*.csv"))
df = pd.concat([pd.read_csv(f, dtype={"basin": str}) for f in fs], ignore_index=True)
df = df.drop_duplicates("basin").sort_values("basin").reset_index(drop=True)
df.to_csv(f"{R}/exact_moment_probe_eps0.1.csv", index=False)
ok = df[df["error"].isna()] if "error" in df else df
print(f"merged basins: {len(df)}  ok: {len(ok)}  errors: {len(df)-len(ok)}")
print(f"median D_exact_moment      = {ok.D_exact_moment.median():.4f}")
print(f"median D_stat_exp2         = {ok.D_stat_exp2.median():.4f}")
print(f"median D_lp_exp2           = {ok.D_lp_exp2.median():.4f}")
print(f"max whole mean shift       = {ok.whole_mean_abs_max.max():.3e}")
print(f"max whole std rel shift    = {ok.whole_std_rel_max.max():.3e}")
print(f"median eps excess max      = {ok.eps_excess_max.median():.4g}")
print(f"max eps excess max         = {ok.eps_excess_max.max():.4g}")
print(f"median eps excess frac     = {ok.eps_excess_frac.median():.4g}")
print(f"max physical excess        = {ok.physical_excess_max.max():.4g}")
print(f"basins with physical excess > 0 : {int((ok.physical_excess_max > 0).sum())} / {len(ok)}")
PY
  cd $M && mkdir -p outbox/id05-adversarial/data
  cp -f $R/exact_moment_probe_eps0.1.csv outbox/id05-adversarial/data/
  echo "shipped: $(md5sum outbox/id05-adversarial/data/exact_moment_probe_eps0.1.csv | cut -d' ' -f1)"
else
  echo "  not all parts done yet, no merge"
fi
