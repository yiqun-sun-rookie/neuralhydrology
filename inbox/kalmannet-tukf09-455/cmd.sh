#!/bin/bash
# TUKF09-455 v2r13: preparation job state; submit training once the technical admission exists.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r13_20260909
P="$ROOT/bundle/kalmannet"
T="$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r13/submit_training_gpu.slurm"
A="$ROOT/status/hpc_technical_admission.json"
JID=$(cat "$ROOT/status/preparation_job_id.txt" 2>/dev/null)
echo "TIME=$(date -Is)  PREPARATION_JOB_ID=$JID"
sacct -j "$JID" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10,NodeList%9 2>&1
if [ -f "$ROOT/status/PREPARATION_FAILED.json" ]; then echo PREPARATION_FAILED; cat "$ROOT/status/PREPARATION_FAILED.json"; tail -c 1500 "$ROOT/logs/prepare-$JID.err" 2>&1; exit 0; fi
if [ ! -f "$A" ]; then echo ADMISSION_NOT_YET; ls -la "$ROOT/status" 2>&1 | tail -6; tail -c 700 "$ROOT/logs/prepare-$JID.out" 2>&1; exit 0; fi
echo TECHNICAL_ADMISSION_PRESENT
echo "ADMISSION_SHA256=$(sha256sum "$A"|cut -d\" \" -f1)"
python -X utf8 -c "import json;a=json.load(open(\"$A\"));r=a.get(\"admitted_runtime\",{});print(\"parallelism\",a.get(\"neural_model_parallelism\"));print(\"cards\",r.get(\"cuda_device_count\"),r.get(\"cuda_device_name\"));print(\"cpus\",r.get(\"slurm_cpus_on_node\"),r.get(\"slurm_cpus_per_task\"));print(\"host\",r.get(\"hostname\"));print(\"eval_authorized\",a.get(\"formal_evaluation_authorized\"))" 2>&1
if [ -d "$ROOT/status/training_submission.lock" ]; then echo TRAINING_ALREADY_SUBMITTED; cat "$ROOT/status/training_job_id.txt" 2>/dev/null; exit 0; fi
grep -E "^#SBATCH (-p|--cpus-per-task|--gres|-t)" "$T"
echo "EXCLUSIVE=$(grep -c -- "--exclusive" "$T" || true)"
mkdir "$ROOT/status/training_submission.lock"
TJ=$(sbatch --parsable "$T"); TJ=${TJ%%;*}
echo "$TJ" > "$ROOT/status/training_job_id.txt"
chmod 444 "$ROOT/status/training_job_id.txt"
echo "TRAINING_JOB_ID=$TJ"
sleep 30
squeue -j "$TJ" -o "%.10i %.10T %.11M %.11l %.9N %.26R" 2>&1
echo TUKF09_455_V2R13_TRAINING_SUBMITTED
