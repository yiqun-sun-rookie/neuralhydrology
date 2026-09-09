#!/bin/bash
# seq=39 read the two probe verdicts from the digest JSONs, not from the log tails.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
P="$ROOT/results/33_transformer_recipe_repair/_repro_probe"
echo "=== STAMP ==="; date -Iseconds
echo "=== DIGEST DIRS ==="
ls -1d "$P"/digests_* 2>&1 || true
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
python - "$P" <<'PY' 2>&1
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
for d in sorted(root.glob("digests_*")):
    print(f"--- {d.name} ---")
    recs = {p.stem: json.loads(p.read_text()) for p in sorted(d.glob("*.json"))}
    if not recs:
        print("  NO DIGESTS"); continue
    for lab, r in recs.items():
        st = r["determinism_state"]
        print(f"  {lab}: det_req={r['deterministic_requested']} algos={st['deterministic_algorithms']} "
              f"cudnn_det={st['cudnn_deterministic']} tf32={st['matmul_allow_tf32']} "
              f"cublas='{st['cublas_workspace_config']}' failed={r['training_failed']}")
        for k, v in sorted(r["weight_sha256"].items()):
            print(f"    {k} {v}")
    for ep in sorted({k for r in recs.values() for k in r["weight_sha256"]}):
        vals = {r["weight_sha256"].get(ep) for r in recs.values()}
        print(f"  {ep}: distinct={len(vals)} identical={len(vals)==1 and None not in vals}")
    e = sorted(recs.values(), key=lambda r: r["label"])[0]["environment"]
    print(f"  env: {e['gpu_name']} torch {e['torch']} cuda {e['cuda']} cudnn {e['cudnn']} node {e['node']}")
PY
echo "=== CROSS-CONDITION ==="
echo "(deterministic epoch002 vs control epoch002 are expected to differ; that is not the test)"
