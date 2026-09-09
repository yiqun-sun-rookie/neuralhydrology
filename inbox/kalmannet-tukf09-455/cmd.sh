#!/bin/bash
# TUKF09-455: wait for the v2r14 offline runtime inputs, verify them, submit preparation.
# Submits nothing if the inputs did not publish and verify.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909
P="$ROOT/bundle/kalmannet"
FINAL="$ROOT/offline_inputs_v2r14"
PENDING="$ROOT/offline_inputs_v2r14.pending.v2r14a"
echo "TIME=$(date -Is)"

echo "=== WAIT FOR THE OFFLINE RUNTIME INPUTS ==="
for i in $(seq 1 90); do
  if [ -d "$FINAL" ]; then echo "PUBLISHED after $((i*20))s"; break; fi
  if ! kill -0 $(cat "$ROOT/status/offline_inputs_download.launched" 2>/dev/null | sed 's/.*pid=//') 2>/dev/null; then
    echo "DOWNLOADER_NO_LONGER_RUNNING at $((i*20))s"; break
  fi
  sleep 20
done
echo "PENDING_BYTES=$(du -sb "$PENDING" 2>/dev/null | cut -f1)"
echo "FINAL_PRESENT=$(test -d "$FINAL" && echo yes || echo no)"
echo "--- download log tail ---"
tail -n 12 "$ROOT/logs/offline-inputs-download.out" 2>/dev/null | cut -c1-400 || true

if [ ! -d "$FINAL" ]; then
  echo "=== THE DOWNLOAD DID NOT PUBLISH; NOTHING WILL BE SUBMITTED ==="
  ls -la "$ROOT" "$ROOT/status" 2>/dev/null || true
  find "$PENDING" -maxdepth 2 -type d 2>/dev/null | head -10 || true
  echo TUKF09_455_V2R14_OFFLINE_INPUTS_NOT_PUBLISHED
  exit 20
fi

echo "=== VERIFY THE PUBLISHED INPUTS ==="
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo CONDA_FAILED; exit 21; }
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
python -X utf8 -B "$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r14/stage_and_train.py" verify-offline-inputs \
  --manifest "$FINAL/manifest.json" \
  --wheelhouse "$FINAL/wheelhouse" \
  --sourcehouse "$FINAL/sourcehouse"
python -X utf8 - "$FINAL/manifest.json" <<'PYEOF'
import json, sys
m = json.load(open(sys.argv[1]))
print("STATUS=" + m["status"])
print("FILES=" + str(m["total_file_count"]) + " BYTES=" + str(m["total_bytes"]))
print("SCHEMA=" + m["schema_version"])
print("SHARED_MODIFIED=" + str(m["shared_nh_final_modified"]))
print("CONTRACT_CHANGED=" + str(m["scientific_contract_changed"]))
ok = m["total_file_count"] == 24 and m["total_bytes"] == 2817756909
print("MATCHES_THE_FROZEN_INVENTORY=" + str(ok))
sys.exit(0 if ok else 22)
PYEOF

echo "=== SUBMIT THE PREPARATION JOB ==="
test ! -f "$ROOT/status/PREPARATION_FAILED.json"
test ! -d "$ROOT/runtime_v2r14"
sinfo -p hgpu4 -N -O NodeHost,StateLong,Gres,GresUsed,CPUsState 2>&1 | head -6
JOB=$(sbatch --parsable "$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r14/probe_gpu.slurm")
echo "$JOB" > "$ROOT/status/preparation_job_id.txt"
echo "PREPARATION_JOB=$JOB"
sleep 20
squeue -j "$JOB" -o "%.10i %.22j %.9P %.8T %.10M %.6D %R" 2>&1 | head -5

echo TUKF09_455_V2R14_PREPARATION_SUBMITTED
