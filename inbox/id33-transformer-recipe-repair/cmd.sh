#!/bin/bash
# seq=69 AUDIT: prove the 8 G1 runs consumed grace_twsa_mm (run config, scaler, LSTM input-weight shape/column norms) and the C4 seed runs did not.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
eval "$(sed -n '/^export MKL/p;/^export OMP/p' src/transformer_recipe_repair/hpc/submit_packed_arms.slurm)"
echo "=== STAMP ==="; date -Iseconds
echo "=== FEATURE ==="; sha256sum src/grace_input_runoff/features/grace_twsa_daily_v01.p; ls -l src/grace_input_runoff/features/
echo "=== CONFIG SHA ==="; sha256sum src/transformer_recipe_repair/configs/g1.yml src/transformer_recipe_repair/configs/c4.yml
for a in G1 G1_s200 G1_s300 G1_s400 G1_s500 G1_s600 G1_s700 G1_s800 C4 C4_s200 C4_s300 C4_s400 C4_s500 C4_s600 C4_s700 C4_s800; do
  d=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_* 2>/dev/null | tail -1)
  echo "##ARM $a dir=$d ndirs=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_* 2>/dev/null | wc -l)"
  [ -n "$d" ] || continue
  python - "$d" <<'PY' 2>&1
import sys, glob, pickle
from pathlib import Path
import yaml, torch
d = Path(sys.argv[1])
cfg = yaml.safe_load(open(d / "config.yml"))
print("  dyn:", cfg["dynamic_inputs"], "| aff:", cfg.get("additional_feature_files"), "| seed:", cfg["seed"], "| model:", cfg["model"], "| epochs:", cfg["epochs"])
sc = sorted(glob.glob(str(d / "train_data" / "train_data_scaler*")))
for f in sc:
    if f.endswith(".yml"):
        s = yaml.safe_load(open(f))
        c = s.get("xarray_feature_center", {}); v = s.get("xarray_feature_scale", {})
        keys = c.get("data_vars", c).keys() if isinstance(c, dict) else []
        ks = [k for k in keys if "grace" in k]
        print("  scaler(yml) grace keys:", ks, "center/scale:", [(c["data_vars"][k]["data"], v["data_vars"][k]["data"]) for k in ks] if ks and "data_vars" in c else "")
    else:
        s = pickle.load(open(f, "rb"))
        c = s["xarray_feature_center"]; v = s["xarray_feature_scale"]
        ks = [k for k in c.data_vars if "grace" in k]
        print("  scaler(p) grace keys:", ks, "center/scale:", [(float(c[k]), float(v[k])) for k in ks])
ck = torch.load(d / "model_epoch030.pt", map_location="cpu")
w = ck["lstm.weight_ih_l0"]
n = [round(float(w[:, i].norm()), 3) for i in range(w.shape[1])]
print("  weight_ih_l0:", tuple(w.shape), "| first 6 col norms:", n[:6], "| statics mean norm:", round(sum(n[6 if w.shape[1] == 33 + 1 else 5:]) / len(n[6 if w.shape[1] == 34 else 5:]), 3))
PY
done
echo "=== DONE ==="
