#!/bin/bash
# TUKF09-455 v2r10: evidence for the FAILED training job. Read only.
# Submits nothing, retries nothing, migrates nothing, writes nothing.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r10_20260904
RR="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
TID=$(cat "$ROOT/status/training_job_id.txt" 2>/dev/null)
echo "TIME=$(date -Is)  TRAINING_JOB_ID=$TID"

echo "=== 1. SLURM FINAL STATE ==="
sacct -j "$TID" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10,Start%20,End%20,NodeList%9 2>&1
sacct -j "$TID" --format=JobID%16,JobName%14,State%12,ExitCode%8,MaxRSS%10,AveCPU%10 2>&1

echo "=== 2. MODELS AND CHECKPOINTS ==="
echo "COMPLETE_UNITS=$(find "$RR/neural" -maxdepth 1 -type d -name "lead_*_seed_*" -not -name "*.pending-*" 2>/dev/null | wc -l) / 9"
echo "PENDING_UNITS=$(find "$RR/neural" -maxdepth 1 -type d -name "lead_*_seed_*.pending-*" 2>/dev/null | wc -l)"
echo "CHECKPOINTS=$(find "$RR/neural" -type f -name "*.pt" 2>/dev/null | wc -l) / 270"
ls -la "$RR/neural" 2>&1
for d in "$RR/neural"/lead_*; do echo "--- $d"; ls -la "$d" 2>&1; done

echo "=== 3. THE THIRTIETH CHECKPOINT (mtime pins the start of the final minute; %h = link count) ==="
find "$RR/neural" -type f -name "epoch_030.pt" -exec stat -c "%y  links=%h  bytes=%s  %n" {} \; 2>&1
find "$RR/neural" -type f -name "epoch_0*.pt" -printf "%TY-%Tm-%Td %TH:%TM:%TS %p\n" 2>/dev/null | sort | tail -3
echo "MANIFEST_IN_FINAL_UNIT=$(ls "$RR/neural/lead_1_seed_0/manifest.sha256.json" 2>/dev/null || echo ABSENT)"
echo "MODEL_SELECTION_IN_FINAL_UNIT=$(ls "$RR/neural/lead_1_seed_0/model_selection.json" 2>/dev/null || echo ABSENT)"

echo "=== 4. CONTROLLER EVENT LOG: LAST THREE EVENTS ==="
tail -n 3 "$RR/control/neural/events.jsonl" 2>&1
echo "EVENT_COUNT=$(wc -l < "$RR/control/neural/events.jsonl" 2>/dev/null)"

echo "=== 5. THE DECIDING STRING ==="
echo "--- events.jsonl:"; grep -c "basin population differs" "$RR/control/neural/events.jsonl" 2>&1
echo "--- training-$TID.err:"; grep -n "basin population differs" "$ROOT/logs/training-$TID.err" 2>&1 | head -3
echo "--- training-$TID.out:"; grep -n "basin population differs" "$ROOT/logs/training-$TID.out" 2>&1 | head -3
for f in "$RR/logs/formal_training_sequence/neural_controller.stderr.log" "$RR/control/neural/neural_controller.stderr.log"; do if [ -f "$f" ]; then echo "--- $f:"; grep -n "basin population differs" "$f" | head -3; fi; done

echo "=== 6. UNIT-RUNNER STDERR TAIL (the traceback) ==="
for f in "$RR/logs/formal_training_sequence/neural_controller.stderr.log" "$RR/control/neural/neural_controller.stderr.log"; do if [ -f "$f" ]; then echo "--- $f ($(wc -c < "$f") bytes)"; tail -c 3000 "$f"; fi; done
echo "--- SLURM stderr tail:"; tail -c 2500 "$ROOT/logs/training-$TID.err" 2>&1
echo "--- SLURM stdout tail:"; tail -c 1200 "$ROOT/logs/training-$TID.out" 2>&1

echo "=== 7. STATUS MARKERS ==="
ls -la "$ROOT/status" 2>&1
echo "SELECTION=$(test -e "$RR/selection" && echo PRESENT || echo ABSENT)  EVALUATION=$(test -e "$RR/evaluation" && echo PRESENT || echo ABSENT)"

echo "=== 8. NODE, QUEUE, LIMITS (for the next version) ==="
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C %.12l" 2>&1
sacctmgr show qos format=Name%20,MaxWall%12,MaxTRESPU%30 -P 2>&1 | head -8
sacctmgr show assoc where user=$USER format=Partition%10,QOS%20,MaxWall%12 -P 2>&1 | head -8
squeue -u $USER -o "%.10i %.12P %.20j %.10T %.11M %.11l %.9N" 2>&1

echo "=== 9. PRESERVED EVIDENCE UNTOUCHED ==="
for r in v2r4 v2r5 v2r6 v2r7 v2r8 v2r9 v2r10; do d=$(ls -d /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_${r}_2026* 2>/dev/null | head -1); echo "ROOT_${r}=${d:-<absent>}"; done
for c in v2 v3 v4 v5; do d=$(ls -d /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_${c}_2026* 2>/dev/null | head -1); echo "CAPSULE_${c}=${d:-<absent>} mode=$(stat -c %a "$d" 2>/dev/null)"; done

echo TUKF09_455_V2R10_FAILURE_EVIDENCE_READ_ONLY_NOTHING_CHANGED
