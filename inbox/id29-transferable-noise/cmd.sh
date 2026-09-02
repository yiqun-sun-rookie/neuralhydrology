#!/bin/bash
# id29-transferable-noise seq=14: emit compact per-length tables for local independent re-settlement.
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
D=results/23_camels_switch_confirmation/noise_axis_training_length_20260902_hpc
cd "$ROOT" || { echo "ROOT_MISSING"; exit 1; }
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final 2>&1 | tail -0

echo "=== SETTLE EXIT DIAGNOSTIC ==="
PYTHONPATH="$ROOT/src:$ROOT/pysite" CAMELS_SWITCH_RESULTS="$ROOT/results/23_camels_switch_confirmation" python -u src/camels_switch_confirmation/scripts/run_noise_axis_training_length.py settle > /tmp/settle_out.txt 2>/tmp/settle_err.txt; echo "exit=$?"; echo "--- stderr ---"; tail -n 15 /tmp/settle_err.txt

echo "=== BUILD TABLES ==="
PYTHONPATH="$ROOT/src:$ROOT/pysite" CAMELS_SWITCH_RESULTS="$ROOT/results/23_camels_switch_confirmation" python - <<'PY'
import json, glob, os, csv
D = os.environ["CAMELS_SWITCH_RESULTS"] + "/noise_axis_training_length_20260902_hpc"
G = ("SNOWPACK","MELTWATER","SM","SUZ","SLZ","ROUTING")
for L in ("L2","L3"):
    recs=[json.load(open(f)) for f in sorted(glob.glob(f"{D}/{L}/learn/*.json"))]
    with open(f"{D}/{L}_learn_per_basin.csv","w",newline="") as fh:
        w=csv.writer(fh); w.writerow(["basin_id","status","winner_anchor","train_objective","own_nse_holdout","m1c0_nse_holdout","anchor_objective_relative_iqr","exact_boundary","outer_5pct"]+[f"rho_{g}" for g in G]+[f"share_{g}" for g in G])
        for r in recs:
            if r["status"]!="success": w.writerow([r["basin_id"],r["status"]]+[""]*(7+12)); continue
            w.writerow([r["basin_id"],"success",r["winner_anchor"],r["train_objective"],r["own_nse_holdout"],r["m1c0_nse_holdout"],r["anchor_objective_relative_iqr"],r["exact_boundary"],r["outer_5pct"]]+list(r["rho"])+list(r["shares"]))
    brecs=[json.load(open(f)) for f in sorted(glob.glob(f"{D}/{L}/borrow/*.json"))]
    donors=sorted({d for r in brecs if r["status"]=="success" for d in r["borrowed"]})
    with open(f"{D}/{L}_borrow_matrix_nse_holdout.csv","w",newline="") as fh:
        w=csv.writer(fh); w.writerow(["donor"]+[r["basin_id"] for r in brecs if r["status"]=="success"])
        for d in donors:
            w.writerow([d]+[r["borrowed"].get(d,"") for r in brecs if r["status"]=="success"])
    with open(f"{D}/{L}_m1c0_per_basin.csv","w",newline="") as fh:
        w=csv.writer(fh); w.writerow(["basin_id","m1c0_nse_holdout","status"])
        for r in brecs: w.writerow([r["basin_id"], r.get("m1c0_nse_holdout",""), r["status"]])
    print(L,"tables written; learn",len(recs),"borrow",len(brecs),"donors",len(donors))
PY

emit() { if [ -f "$1" ]; then echo "=== FILE $1 ==="; cat "$1"; echo; echo "=== END FILE ==="; else echo "=== MISSING $1 ==="; fi; }
emit "$D/summary.json"
for L in L2 L3; do emit "$D/${L}_learn_per_basin.csv"; emit "$D/${L}_m1c0_per_basin.csv"; emit "$D/${L}_borrow_matrix_nse_holdout.csv"; done
emit "$D/frozen_basin_list.csv"
echo "=== SHA256 ==="
sha256sum "$D"/summary.json "$D"/p0_report.json "$D"/*_learn_per_basin.csv "$D"/*_borrow_matrix_nse_holdout.csv "$D"/*_m1c0_per_basin.csv "$D"/frozen_basin_list.csv 2>&1 || true
echo "=== DONE ==="
