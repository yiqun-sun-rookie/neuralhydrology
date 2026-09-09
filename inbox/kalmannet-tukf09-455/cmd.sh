#!/bin/bash
# TUKF09-455 v2r12: preparation job state and readiness to submit training. Read only.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r12_20260908
JID=$(cat "$ROOT/status/preparation_job_id.txt" 2>/dev/null)
echo "TIME=$(date -Is)  PREPARATION_JOB_ID=$JID"
sacct -j "$JID" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10,NodeList%9,Start%20,End%20 2>&1
squeue -j "$JID" -o "%.10i %.10T %.30R" 2>&1 | tail -2
echo "=== STATUS ARTIFACTS ==="
for f in preparation_probe.json hpc_technical_admission.json staged_training_sources.json initial_bundle_verification.json PREPARATION_FAILED.json; do if [ -f "$ROOT/status/$f" ]; then echo "$f SHA256=$(sha256sum "$ROOT/status/$f"|cut -d" " -f1) SIZE=$(stat -c %s "$ROOT/status/$f")"; else echo "$f ABSENT"; fi; done
ls -la "$ROOT/status" 2>&1
echo "=== RUNTIME IDENTITY ==="
if [ -f "$ROOT/status/preparation_probe.json" ]; then python -X utf8 -c "import json;p=json.load(open(\"$ROOT/status/preparation_probe.json\"));r=p.get(\"runtime\",{});[print(f\"  {k}: {r.get(k)}\") for k in (\"hostname\",\"cuda_device_count\",\"cuda_device_name\",\"slurm_cpus_on_node\",\"slurm_cpus_per_task\",\"slurm_job_cpus_per_node_raw\",\"exclusive_node_runtime_evidence_passed\",\"slurm_job_gpus\",\"nvidia_gpu_uuids\")]" 2>&1; else echo NO_PROBE; fi
echo "=== STAGED DATA ==="
du -sh "$ROOT/bundle/kalmannet/G:" 2>/dev/null || true
find "$ROOT/bundle/kalmannet" -maxdepth 3 -name camels_us -type d 2>/dev/null | head -3
echo "=== PREPARE LOG TAIL ==="
tail -c 2000 "$ROOT/logs/prepare-$JID.out" 2>&1
tail -c 1200 "$ROOT/logs/prepare-$JID.err" 2>&1
echo "=== PARTITION ==="
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C %.14G" 2>&1
echo TUKF09_455_V2R12_PREPARATION_STATE
