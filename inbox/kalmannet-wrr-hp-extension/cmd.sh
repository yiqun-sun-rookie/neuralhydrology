#!/usr/bin/env bash
# Read-only progress query for the authorized six-run validation-replication array.
set -euo pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_finalist_replication_20260907
EXP="$ROOT/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
JOB_ID="$(cat "$ROOT/array_job_id.txt")"
[[ "$JOB_ID" =~ ^[0-9]+$ ]]
echo "NOW=$(date -Is)"
echo "JOB_ID=$JOB_ID"
echo "=== SQUEUE ==="
squeue -j "$JOB_ID" -o '%i|%j|%T|%P|%M|%l|%R' || true
echo "=== SACCT ==="
sacct -j "$JOB_ID" -X -n -P --format=JobID,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList || true
echo "=== RUN_SUMMARY ==="
python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
exp = root / 'repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'
combos = [json.loads(s) for s in (exp / 'combos.jsonl').read_text().splitlines() if s.strip()]
summary = []
for combo in combos:
    item = {k: combo[k] for k in ('index','run_id','lr','hidden_size','num_layers','in_out_mult','seed')}
    run_paths = list(exp.glob('runs/formal_seed%d_gpu/idx%04d_*' % (combo['seed'], combo['index'])))
    item['run_directory_count'] = len(run_paths)
    if len(run_paths) > 1:
        item['error'] = 'multiple run directories'
    if len(run_paths) == 1:
        run = run_paths[0]
        ep = run / 'results/epoch_log.jsonl'
        records = []
        if ep.is_file():
            for line in ep.read_text(errors='replace').splitlines():
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
        item['completed_epoch_records'] = len(records)
        if records:
            item['last_epoch_zero_based'] = records[-1].get('epoch_zero_based')
            item['last_epoch_val_screening_nse'] = records[-1].get('val_screening_nse')
            item['last_epoch_lr'] = records[-1].get('lr_used_this_epoch')
            item['rollbacks_so_far'] = sum(int(x.get('grad_explosion_rollbacks',0)) for x in records)
            item['nonfinite_skips_so_far'] = sum(int(x.get('nan_inf_skips',0)) for x in records)
        cell_path = run / 'cell_metrics.json'
        item['cell_metrics_exists'] = cell_path.is_file()
        if cell_path.is_file():
            cell = json.loads(cell_path.read_text())
            vs = cell.get('validation_scoring', {})
            el = cell.get('epoch_log_summary', {})
            item['cell'] = {
                'cell_run_id': cell.get('run_id'), 'cell_seed': cell.get('seed'),
                'finished_at': cell.get('finished_at'), 'train_seconds': cell.get('train_seconds'),
                'pooled_mean_actual_leads_1_12': vs.get('pooled_mean_leads_1_12_corrected_def'),
                'best_checkpoint_sha256': vs.get('best_checkpoint_sha256'),
                'best_epoch_zero_based': vs.get('best_epoch_zero_based'),
                'epochs_run': el.get('epochs_run'), 'stop_epoch_zero_based': el.get('stop_epoch_zero_based'),
                'rollbacks_total': el.get('grad_explosion_rollbacks_total'),
                'nonfinite_skips_total': el.get('nan_inf_skips_total')
            }
    audits = []
    for ap in exp.glob('audits/*_formal_*.json'):
        try:
            audit = json.loads(ap.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if audit.get('run_id') == combo['run_id']:
            audits.append({'file': ap.name, 'launcher_status': audit.get('launcher_status'),
              'started_at': audit.get('started_at'), 'finished_at': audit.get('finished_at'),
              'slurm_job_id': audit.get('slurm_job_id'), 'slurm_array_task_id': audit.get('slurm_array_task_id'),
              'hostname': audit.get('hostname'), 'held_out_test_loaded': audit.get('held_out_test_loaded'),
              'runtime': audit.get('runtime')})
    item['audits'] = audits
    summary.append(item)
print(json.dumps({'run_count': len(summary), 'runs': summary}, indent=2))
PY
echo "=== LOG_MILESTONES ==="
for f in "$ROOT"/logs/slurm-"$JOB_ID"_*.out; do
  [ -f "$f" ] || continue
  echo "--- $f"
  grep -E 'EXPECTED_RUNTIME_MATCH|EpochSummary|Early stopping|cell_metrics written|M\(leads 1-12\)|finished=|Traceback|FATAL|Error' "$f" | tail -n 8 || true
done
echo "=== STDERR_NONEMPTY ==="
found=0
for f in "$ROOT"/logs/slurm-"$JOB_ID"_*.err; do
  [ -s "$f" ] || continue
  found=1
  echo "--- $f"
  tail -n 12 "$f"
done
[ "$found" -eq 0 ] && echo none
