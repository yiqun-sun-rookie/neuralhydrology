#!/usr/bin/env bash
# ID32 seq=9 : read the learned per-head attention decay out of the T03 and T05 checkpoints.
# Pure tensor inspection of files that already exist. No training, no sbatch, no GPU.
set -o pipefail
ID32=/data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo
cd "$ID32" || exit 1
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
echo "=== STAMP ==="; date -Is

python - <<'PY' 2>&1 || true
import torch, math
from pathlib import Path
import torch.nn.functional as F
res = Path("results/32_transformer_inductive_bias")
print("initialisation was slope 2^-2,2^-4,2^-6,2^-8 -> memory 4, 16, 64, 256 days\n")
for arm in ("T03","T05"):
    hits = sorted(res.glob(f"{arm}/*/model_epoch030.pt"))
    if not hits:
        print(arm, "NO_CHECKPOINT"); continue
    sd = torch.load(hits[0], map_location="cpu")
    if not isinstance(sd, dict): print(arm,"unexpected checkpoint type"); continue
    keys = [k for k in sd if "decay_logit" in k]
    if not keys: print(arm,"no decay_logit in checkpoint; keys sample:",list(sd)[:6]); continue
    print(f"--- {arm}  ({hits[0].parent.name}) ---")
    for k in sorted(keys):
        slopes = F.softplus(sd[k].float())
        mem = 1.0/slopes
        print("  %-34s slope=%s" % (k, " ".join(f"{v:.4f}" for v in slopes.tolist())))
        print("  %-34s memory_days=%s" % ("", " ".join(f"{v:7.2f}" for v in mem.tolist())))
    print()
PY
echo "ID32_DECAY_READOUT_SEQ9_COMPLETE"
