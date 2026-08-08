#!/usr/bin/env bash
#SBATCH -J a64-verify
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 02:00:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err

set -o pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export MKL_THREADING_LAYER=GNU

ROOT=/data1/home/sunyiq/autoresearch64
CAMELS=/data1/home/sunyiq/neuralhydrology/data/camels_us
cd "$ROOT" || exit 1
export PYTHONPATH="$ROOT/src:$PYTHONPATH"

echo "=== 1. independent per-basin verification (correct flag this time) ==="
python src/unified_autoresearch/scripts/verify_development_artifacts.py \
  --source-root runs/unified_autoresearch/development_source_real_64_hpc \
  --package-root runs/unified_autoresearch/development_packages_real_64_hpc \
  --camels-root "$CAMELS" \
  --selection src/unified_autoresearch/selection/development_basins_64_v1.json \
  --report runs/unified_autoresearch/VERIFICATION_64_HPC.json 2>&1 | tail -30

echo "=== 2. platform-independent CONTENT digest (not byte digest) ==="
python - <<'PY'
import hashlib, pathlib, pandas as pd
root = pathlib.Path("runs/unified_autoresearch/development_source_real_64_hpc")
for name, cols in (("targets.parquet", ["basin","date","qobs"]), ("features.parquet", ["basin","date","prcp","tmin","tmax","srad","vp"])):
    f = pd.read_parquet(root / name)
    f["basin"] = f["basin"].astype(str).str.zfill(8)
    f["date"] = pd.to_datetime(f["date"]).dt.strftime("%Y-%m-%d")
    f = f.sort_values(["basin","date"]).reset_index(drop=True)
    digest = hashlib.sha256()
    for row in f[cols].itertuples(index=False):
        digest.update(("|".join(f"{v:.12g}" if isinstance(v, float) else str(v) for v in row) + "\n").encode())
    print(f"{name}: rows={len(f)} content_sha256={digest.hexdigest()}")
PY

echo "=== 3. why do the JSON bytes differ? line endings ==="
python - <<'PY'
import pathlib
p = pathlib.Path("runs/unified_autoresearch/development_source_real_64_hpc/static_attributes.json")
raw = p.read_bytes()
print("CRLF count:", raw.count(b"\r\n"), "| bare LF count:", raw.count(b"\n") - raw.count(b"\r\n"))
PY

echo "=== 4. eligibility content vs the Windows record (ignoring embedded package hash) ==="
python - <<'PY'
import json, hashlib, pathlib
r = json.loads(pathlib.Path("runs/unified_autoresearch/BASIN_ELIGIBILITY_64_HPC.json").read_text())
core = {k: r[k] for k in ("schema_version","decided_from","protocols","thresholds","basins","standard_basins","unstable_basins")}
blob = json.dumps(core, sort_keys=True, separators=(",",":")).encode()
print("eligibility CONTENT sha256 (excludes package_manifest_sha256):", hashlib.sha256(blob).hexdigest())
print("standard:", len(r["standard_basins"]), "unstable:", len(r["unstable_basins"]))
print("unstable list:", ",".join(r["unstable_basins"]))
PY
