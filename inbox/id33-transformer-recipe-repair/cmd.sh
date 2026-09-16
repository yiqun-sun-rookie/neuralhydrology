#!/bin/bash
# seq=64 ID35 smoke take 3: feature pickle v02 (index named "date"), registry hash updated. Then smoke on GPU.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
tar -xzf ~/hpc_mailbox/payload/id33-transformer-recipe-repair/id35_g1_v02.tar.gz -C "$ROOT"
sha256sum src/grace_input_runoff/features/grace_twsa_daily_v01.p src/transformer_recipe_repair/registry/experiments.csv
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 | tail -1
rm -rf results/35_grace_input_runoff/_smoke; mkdir -p results/35_grace_input_runoff/_smoke logs/35_grace_input_runoff
OUT=$(sbatch src/grace_input_runoff/hpc/smoke.slurm 2>&1); echo "$OUT"
J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true); [ -n "$J" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "smoke_job=$J"
for i in $(seq 1 120); do ST=$(sacct -j "$J" -X -n --format=State 2>/dev/null | head -1 | tr -d ' '); case "$ST" in RUNNING|PENDING|"") sleep 10;; *) echo "state=$ST after ${i}0s"; break;; esac; done
sacct -j "$J" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10,NodeList%8 2>&1
echo "=== SMOKE OUTPUT ==="
grep -vE 'Evaluation:|it/s\]|^20[0-9-]+ [0-9:,]+: [a-z_]+: ' logs/35_grace_input_runoff/smoke-$J.out 2>/dev/null | tail -20
echo "-- err tail --"; tail -n 12 logs/35_grace_input_runoff/smoke-$J.err 2>/dev/null | grep -vE 'FutureWarning|weights_only|torch.load'
D=$(ls -d results/35_grace_input_runoff/_smoke/grace_input_runoff_G1_SMOKE_* 2>/dev/null | tail -1); echo "run_dir=$D"
grep -E 'Epoch 1 average|Median validation' "$D/output.log" 2>/dev/null | tail -2
python - "$D" <<'PY' 2>/dev/null
import sys, json, pickle
from pathlib import Path
d = Path(sys.argv[1])
s = json.load(open("results/35_grace_input_runoff/_smoke/smoke.json")); print("failed=", s["training_failed"], "| weights=", list(s["weight_sha256"]))
# did the model actually see 6 dynamic inputs? read the scaler
import yaml
sc = yaml.safe_load(open(d/"train_data/train_data_scaler.yml"))
keys = [k for k in (sc.get("xarray_feature_center") or {}).get("data_vars", {})] if isinstance(sc.get("xarray_feature_center"), dict) else []
print("scaler feature keys:", keys[:8])
PY
