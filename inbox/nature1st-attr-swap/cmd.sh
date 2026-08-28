#!/bin/bash
# nature1st-attr-swap seq=114 -- armJ (china min15) watchdog, seeds 42/43/44
# s42=215195 COMPLETED (INCONCLUSIVE), s44=215730 COMPLETED (INCONCLUSIVE, A40).
# Waiting on 215729 (s43). NO submission this round -- all three seeds already exist.
# NO set -e. pipefail only. Every grep/tail guarded with || true.
set -o pipefail

RUN=/data1/home/sunyiq/nature_1st
cd "$RUN" || { echo "FATAL: cannot cd $RUN"; exit 1; }
echo "pwd=$(pwd)  date=$(date '+%F %T')"

echo "=== A. QUEUE / ACCOUNTING (all armJ seeds) ==="
echo "--- squeue ---"
squeue -u "$USER" -o '%.11i %.26j %.9T %.10M %.9N %.9P' 2>&1 | grep -Ei 'armJ|JOBID' || true
echo "--- sacct ---"
sacct -S 2026-08-27 -u "$USER" -X --format=JobID%11,JobName%26,State%12,ExitCode%8,Elapsed%11,NodeList%9 2>&1 | grep -Ei 'armJ|JobID' || true

echo "=== B. LOGS ==="
found_log=0
for f in "$RUN"/logs/attr_swap/armJ_china_min15*.out; do
  [ -f "$f" ] || continue
  found_log=1
  echo "--- $(basename "$f")"
  stat -c '    bytes=%s  mtime=%y' "$f" 2>/dev/null || true
  echo "    [guard] (MUST say 15 attributes):"
  grep '\[guard\]' "$f" 2>/dev/null | tail -4 | sed 's/^/      /' || true
  echo "    [gpu card]:"
  grep -Ei 'device name|GPU [0-9]|RTX|A40|Tesla|NVIDIA' "$f" 2>/dev/null | head -3 | sed 's/^/      /' || true
  echo "    [errors]:"
  ec=$(grep -Ec 'RuntimeError|Traceback|CUDA error|FATAL|Killed|out of memory' "$f" 2>/dev/null || true)
  if [ "${ec:-0}" != "0" ]; then
    grep -E 'RuntimeError|Traceback|CUDA error|FATAL|Killed|out of memory' "$f" 2>/dev/null | tail -8 | sed 's/^/      /' || true
  else
    echo "      none"
  fi
  echo "    [progress, last 8]:"
  grep -E '^Epoch|Best val median NSE|Done\.' "$f" 2>/dev/null | tail -8 | sed 's/^/      /' || true
  echo "    [Done. marker]:"
  grep -c '^Done\.' "$f" 2>/dev/null | sed 's/^/      Done_lines=/' || true
done
[ "$found_log" = "0" ] && echo "  (no armJ log files matched)"

echo "=== C. OUTPUT DIRS / COMPLETION ==="
for S in 42 43 44; do
  d="$RUN/models/q_lstm_armJ_hpc_s${S}"
  if [ -d "$d" ]; then
    echo "  s${S}: dir EXISTS"
    if [ -f "$d/eval_val_per_station.csv" ]; then
      echo "    eval_val_per_station.csv PRESENT ($(stat -c '%s bytes, %y' "$d/eval_val_per_station.csv" 2>/dev/null))"
    else
      echo "    eval_val_per_station.csv absent"
    fi
    if [ -f "$d/best_metrics.json" ]; then
      echo "    best_metrics.json [INTERIM unless Done./COMPLETED]:"
      tr -d '\n' < "$d/best_metrics.json" 2>/dev/null | cut -c1-400 | sed 's/^/      /' || true
      echo ""
    fi
  else
    echo "  s${S}: no output dir"
  fi
done

echo "=== D. PAIRED ANALYSIS (per available armJ seed) ==="
if [ -f "$RUN/models/q_lstm_armJ_hpc_s42/eval_val_per_station.csv" ]; then
  source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || true
  conda activate nh_final 2>/dev/null || true
  python - <<'PYEOF' 2>&1
import os
try:
    import numpy as np, pandas as pd
except Exception as e:
    print("  IMPORT FAIL:", e); raise SystemExit(0)

RUN = "/data1/home/sunyiq/nature_1st"
BASE = [("armC  best-US-8", "q_lstm_usminus4_hpc_s42"),
        ("armI  16-item",   "q_lstm_armI_hpc_s42"),
        ("armG",            "q_lstm_armG_hpc_s42")]

def load(d):
    p = os.path.join(RUN, "models", d, "eval_val_per_station.csv")
    if not os.path.exists(p):
        return None
    try:
        return pd.read_csv(p)
    except Exception as e:
        print("  read fail", d, e); return None

def boot_ci(diff, n=5000):
    rng = np.random.default_rng(0)
    k = len(diff)
    if k == 0: return (float('nan'), float('nan'))
    idx = rng.integers(0, k, size=(n, k))
    b = np.median(diff[idx], axis=1)
    return float(np.percentile(b, 2.5)), float(np.percentile(b, 97.5))

avail = []
for seed in (42, 43, 44):
    tgt = load(f"q_lstm_armJ_hpc_s{seed}")
    if tgt is None:
        print(f"\n#### armJ seed {seed}: eval csv not present yet")
        continue
    avail.append(seed)
    print(f"\n#### armJ seed {seed}: n={len(tgt)}  median_NSE={tgt['nse'].median():.4f}")
    for label, d in BASE:
        b = load(d)
        if b is None:
            print(f"  vs {label}: baseline MISSING ({d})"); continue
        cols = ['station', 'nse'] + (['stratum'] if 'stratum' in tgt.columns else [])
        m = tgt[cols].merge(b[['station', 'nse']], on='station', suffixes=('_J', '_B'))
        if len(m) == 0:
            print(f"  vs {label}: no overlapping stations"); continue
        diff = (m['nse_J'] - m['nse_B']).values.astype(float)
        diff = diff[np.isfinite(diff)]
        mj, mb = m['nse_J'].median(), m['nse_B'].median()
        pmd = float(np.median(diff))
        lo, hi = boot_ci(diff)
        worse = int((diff < 0).sum()); better = int((diff > 0).sum())
        d10 = float((diff < -0.10).mean() * 100.0)
        u10 = float((diff > 0.10).mean() * 100.0)
        print(f"  vs {label}  (paired n={len(diff)})")
        print(f"    median armJ={mj:.4f}  median base={mb:.4f}  diff_of_medians={mj-mb:+.4f}")
        print(f"    PAIRED median diff = {pmd:+.4f}   95%CI [{lo:+.4f}, {hi:+.4f}]")
        print(f"    worse={worse}  better={better}   drop>0.10 = {d10:.1f}%   gain>0.10 = {u10:.1f}%")
        if label.startswith("armC"):
            verdict = "SUFFICIENT" if (pmd >= -0.010 and d10 <= 20.0) else ("VETO" if (pmd < -0.030 or d10 > 35.0) else "INCONCLUSIVE")
            print(f"    >>> PRIMARY CRITERION seed {seed}: {verdict}  (need pmd>=-0.010 AND drop<=20.0%)")
        if 'stratum' in m.columns:
            for s, g in m.groupby('stratum'):
                sd = (g['nse_J'] - g['nse_B']).values.astype(float)
                sd = sd[np.isfinite(sd)]
                if len(sd) == 0: continue
                print(f"      stratum {s!s:>14}  n={len(sd):4d}  paired_med={np.median(sd):+.4f}  drop>0.10={100.0*(sd<-0.10).mean():.1f}%")

if len(avail) > 1:
    print(f"\n#### SEED-POOLED vs armC (seeds available: {avail})")
    b = load("q_lstm_usminus4_hpc_s42")
    if b is not None:
        meds = []
        for seed in avail:
            t = load(f"q_lstm_armJ_hpc_s{seed}")
            m = t[['station', 'nse']].merge(b[['station', 'nse']], on='station', suffixes=('_J', '_B'))
            dd = (m['nse_J'] - m['nse_B']).values.astype(float)
            dd = dd[np.isfinite(dd)]
            meds.append((seed, float(np.median(dd)), float((dd < -0.10).mean() * 100.0)))
        for seed, pm, dr in meds:
            print(f"    seed {seed}: paired_med={pm:+.4f}  drop>0.10={dr:.1f}%")
        mp = float(np.mean([x[1] for x in meds])); md = float(np.mean([x[2] for x in meds]))
        print(f"    mean of per-seed paired medians = {mp:+.4f}")
        print(f"    mean of per-seed drop>0.10      = {md:.1f}%")
        agg = "SUFFICIENT" if (mp >= -0.010 and md <= 20.0) else ("VETO" if (mp < -0.030 or md > 35.0) else "INCONCLUSIVE")
        print(f"    >>> PRIMARY CRITERION on seed-mean: {agg}")
PYEOF
else
  echo "  armJ s42 eval_val_per_station.csv not present -- unexpected, s42 already COMPLETED."
fi

echo "=== E. GPU CAPACITY ==="
sinfo -p hgpu2p,hgpu2,hgpu4 -o '%.10P %.8t %.6D %.20N' 2>&1 | head -20 || true

echo "=== END seq=114 ==="
