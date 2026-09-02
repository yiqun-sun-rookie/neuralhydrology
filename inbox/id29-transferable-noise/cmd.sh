#!/bin/bash
# id29-transferable-noise seq=13: final training-length settle; emit summary + per-basin tables.
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
D=results/23_camels_switch_confirmation/noise_axis_training_length_20260902_hpc
cd "$ROOT" || { echo "ROOT_MISSING"; exit 1; }
echo "=== SACCT ==="
sacct -j 218675,218676 -X --format=JobID%10,JobName%16,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 || true
echo "=== PROGRESS ==="
for L in L2 L3; do echo "$L learn $(ls "$D/$L/learn" 2>/dev/null | grep -c json)/46  borrow $(ls "$D/$L/borrow" 2>/dev/null | grep -c json)/46"; done
echo "=== RESETTLE (idempotent, read-only over the JSONs) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final 2>&1 | tail -0
PYTHONPATH="$ROOT/src:$ROOT/pysite" CAMELS_SWITCH_RESULTS="$ROOT/results/23_camels_switch_confirmation" python -u src/camels_switch_confirmation/scripts/run_noise_axis_training_length.py settle > /dev/null 2>&1 || echo "settle returned nonzero"
emit() { if [ -f "$1" ]; then echo "=== FILE $1 ==="; cat "$1"; echo; echo "=== END FILE ==="; else echo "=== MISSING $1 ==="; fi; }
emit "$D/summary.json"
echo "=== PER-BASIN own/m1c0 (L2,L3) ==="
PYTHONPATH="$ROOT/src:$ROOT/pysite" CAMELS_SWITCH_RESULTS="$ROOT/results/23_camels_switch_confirmation" python - <<'PY' 2>&1 | head -60
import json,glob,os
D=os.environ["CAMELS_SWITCH_RESULTS"]+"/noise_axis_training_length_20260902_hpc"
for L in ("L2","L3"):
    fs=sorted(glob.glob(f"{D}/{L}/learn/*.json"))
    if not fs: print(f"{L}: no learn records"); continue
    rows=[json.load(open(f)) for f in fs]
    good=[r for r in rows if r["status"]=="success"]
    print(f"{L}: {len(good)}/{len(rows)} success; winners:", {r['winner_anchor'] for r in good[:0]} or "")
    import statistics as st
    print("   median own_nse", round(st.median(r["own_nse_holdout"] for r in good),5),
          " median m1c0", round(st.median(r["m1c0_nse_holdout"] for r in good),5))
    bnd=sum(r.get("exact_boundary",0) for r in good); print("   exact-boundary params:", bnd, "/", 6*len(good))
PY
echo "=== LOG TAILS ==="
for f in logs/id29-trlen-L3_218676.out; do [ -f "$f" ] && { echo "--- $f ---"; tail -n 6 "$f"; }; done
for f in logs/id29-trlen-L2_218675.err logs/id29-trlen-L3_218676.err; do [ -f "$f" ] && { s=$(wc -c < "$f"); echo "--- $f ($s bytes) ---"; [ "$s" -gt 0 ] && tail -n 12 "$f"; }; done
echo "=== DONE ==="
