#!/bin/bash
# kalmannet-daily-perbasin sequence=102: READ-ONLY observation of training job 225203 (basin 02102908, launch seq 100).
set -o pipefail
echo "channel=kalmannet-daily-perbasin sequence=102 purpose=read-only-observe-train-02102908-job225203"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908
REQ=$ROOT/runtime/train_02102908_A40_launcher_seq100
RUN=$ROOT/runs/DAILY_CAMELS_KNET_PER_BASIN_21_DEVELOPMENT_V2_20260908_BASIN_02102908_A40_TRAIN1_SEQ100
JOB=225203
echo "QUERY_ACCOUNTING_BEGIN"
timeout 20s sacct -X -n -P -j "$JOB" --format=JobIDRaw,JobName,State,ExitCode,ElapsedRaw,AllocCPUS,ReqTRES,AllocTRES,NodeList,Submit,Start,End
echo "QUERY_ACCOUNTING_EXIT=$?"
echo "QUERY_QUEUE_BEGIN"
timeout 20s squeue -j "$JOB" -h -o '%i|%T|%P|%R|%S|%C|%b|%M' 2>&1
echo "QUERY_QUEUE_EXIT=$?"
STATE=$(timeout 20s sacct -X -n -P -j "$JOB" --format=State | head -n 1)
echo "STATE=$STATE"
emit_file() {
  f="$1"
  if [ -f "$f" ]; then
    echo "FILE_BEGIN path=$f bytes=$(stat -c %s "$f") sha256=$(sha256sum "$f" | cut -c1-64)"
    base64 "$f"
    echo "FILE_END path=$f"
  else
    echo "FILE_ABSENT path=$f"
  fi
}
hash_file() {
  f="$1"
  if [ -f "$f" ]; then
    echo "FILE_HASH path=$f bytes=$(stat -c %s "$f") sha256=$(sha256sum "$f" | cut -c1-64)"
  else
    echo "FILE_ABSENT path=$f"
  fi
}
echo "PROGRESS_BEGIN"
if [ -d "$RUN" ]; then
  echo "run_directory_present=1 checkpoints=$(ls "$RUN/checkpoints" 2>/dev/null | grep -c '^epoch_') predictions=$(ls "$RUN/predictions" 2>/dev/null | grep -c '^epoch_') attempts=$(ls "$RUN/attempts" 2>/dev/null | grep -c '^epoch_')"
  echo "newest_checkpoint=$(ls -t "$RUN/checkpoints" 2>/dev/null | head -n 1) completion_marker=$([ -f "$RUN/completion.marker.json" ] && echo present || echo absent)"
else
  echo "run_directory_present=0"
fi
for d in environment_probe zero_update_gate training_process verifier_process; do
  if [ -f "$REQ/evidence/$d/terminal.json" ]; then echo "stage=$d terminal=present"; elif [ -f "$REQ/evidence/$d/launch.json" ]; then echo "stage=$d terminal=absent launch=present"; else echo "stage=$d not_started"; fi
done
if [ -f "$REQ/slurm-$JOB.stdout" ]; then echo "SLURM_STDOUT_TAIL_BEGIN"; tail -n 12 "$REQ/slurm-$JOB.stdout"; echo "SLURM_STDOUT_TAIL_END"; fi
echo "PROGRESS_END"
case "$STATE" in
  COMPLETED|FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|CANCELLED*)
    echo "TERMINAL=1"
    emit_file "$REQ/slurm-$JOB.stdout"
    emit_file "$REQ/slurm-$JOB.stderr"
    emit_file "$REQ/execution_ownership.json"
    emit_file "$REQ/submission_seq100.receipt.json"
    emit_file "$REQ/admission.json"
    emit_file "$REQ/evidence/worker_result.json"
    for d in environment_probe zero_update_gate training_process verifier_process; do
      emit_file "$REQ/evidence/$d/terminal.json"
    done
    emit_file "$REQ/evidence/zero_update_gate/stdout.bin"
    emit_file "$REQ/evidence/training_process/stdout.bin"
    emit_file "$REQ/evidence/training_process/stderr.bin"
    emit_file "$REQ/evidence/verifier_process/stderr.bin"
    emit_file "$REQ/evidence/audit/independent_verification_report.json"
    emit_file "$RUN/completion.marker.json"
    hash_file "$RUN/result_summary.json"
    hash_file "$RUN/manifest.sha256.json"
    hash_file "$RUN/preflight.json"
    hash_file "$RUN/epoch_history.json"
    if [ -f "$RUN/result_summary.json" ]; then
      echo "SCORES_JSON_BEGIN"
      /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - "$RUN/result_summary.json" <<'KDPP_READ_ONLY_SCORES'
import hashlib, json, sys
raw = open(sys.argv[1], 'rb').read()
result = json.loads(raw)
best = int(result['best_epoch'])
history = result['history']
extract = {
    'result_summary_sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw), 'best_epoch': best,
    'objectives_728': {'epoch_zero': result.get('epoch_zero_checkpoint_objective_728'), 'best': result.get('best_checkpoint_objective_728'), 'last': result.get('last_checkpoint_objective_728')},
    'comparisons': result.get('comparisons'),
    'kalmannet_minus_ukf_nse_by_lead': result.get('kalmannet_minus_unscented_kalman_filter_nse_by_lead'),
    'kalmannet_minus_ukf_mean_nse': result.get('kalmannet_minus_unscented_kalman_filter_mean_nse'),
    'relative_accuracy_status': result.get('relative_accuracy_status'),
    'scientific_gate_evidence': result.get('scientific_gate_evidence'),
    'scientific_capability_status': result.get('scientific_capability_status'),
    'technical_success': result.get('technical_success'), 'terminal_state': result.get('terminal_state'),
    'convergence_status': result.get('convergence_status'), 'formal_evaluation_access_count': result.get('formal_evaluation_access_count'),
    'correction_cap': result.get('correction_cap'), 'diagnostics': result.get('diagnostics'), 'resources': result.get('resources'),
    'divergence_kinds': result.get('divergence_kinds'), 'completed_epoch': result.get('completed_epoch'), 'optimizer_steps': result.get('optimizer_steps'),
    'best_row': {key: history[best].get(key) for key in ('epoch', 'checkpoint_objective_728', 'reporting_objective_712', 'nse_by_lead', 'mse_by_lead', 'validation_saturation_fraction', 'training_objective', 'gradient_norm_before_clip')},
    'history_summary': {'rows': len(history), 'training_objective_first': history[1].get('training_objective') if len(history) > 1 else None, 'training_objective_last': history[-1].get('training_objective'), 'gradient_norm_first': history[1].get('gradient_norm_before_clip') if len(history) > 1 else None, 'gradient_norm_last': history[-1].get('gradient_norm_before_clip'), 'unique_parameter_sha256': len({row.get('parameter_sha256') for row in history})},
    'read_scope': {'files_read': 1, 'checkpoints_read': 0, 'prediction_arrays_read': 0, 'formal_evaluation_read': 0, 'submissions': 0},
}
print(json.dumps(extract, sort_keys=True, separators=(',', ':')))
KDPP_READ_ONLY_SCORES
      echo "SCORES_JSON_END"
    fi
    ;;
  *)
    echo "TERMINAL=0"
    ;;
esac
echo "READ_ONLY_OBSERVE_COMPLETE submissions=0 cancellations=0 modifications=0"
