#!/usr/bin/env bash
# Read-only status for this isolated six-task array; no retry/cancel/training.
set -euo pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_finalist_replication_20260907
JOB_ID="$(cat "$ROOT/array_job_id.txt")"
[[ "$JOB_ID" =~ ^[0-9]+$ ]]
date -Is
squeue -j "$JOB_ID" -o '%i|%j|%T|%P|%M|%l|%R' || true
sacct -j "$JOB_ID" -X -n -P --format=JobID,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList || true
python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
exp = root / 'repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'
report = {'deployment': json.loads((root / 'DEPLOYMENT_RECEIPT.json').read_text()), 'runs': []}
combos = [json.loads(s) for s in (exp / 'combos.jsonl').read_text().splitlines() if s.strip()]
for combo in combos:
    item = {'index': combo['index'], 'run_id': combo['run_id'], 'seed': combo['seed'],
            'hidden_size': combo['hidden_size'], 'in_out_mult': combo['in_out_mult'], 'learning_rate': combo['lr']}
    paths = list(exp.glob('runs/formal_seed%d_gpu/idx%04d_*' % (combo['seed'], combo['index'])))
    item['run_directory_count'] = len(paths)
    if len(paths) > 1:
        raise RuntimeError('Multiple output directories for one authorized run')
    if paths:
        run = paths[0]
        item['run_dir'] = str(run)
        epoch_path = run / 'results/epoch_log.jsonl'
        if epoch_path.is_file():
            # Running writer may have an unfinished final line; never invent a record.
            lines = epoch_path.read_text().splitlines(keepends=True)
            complete = [json.loads(s) for s in lines if s.strip() and s.endswith('\n')]
            item['completed_epochs'] = len(complete)
            if complete:
                item['first_epoch'] = complete[0]
                item['last_epoch'] = complete[-1]
        cell_path = run / 'cell_metrics.json'
        if cell_path.is_file():
            item['cell_metrics'] = json.loads(cell_path.read_text())
    audits = []
    for path in exp.glob('audits/*_formal_*.json'):
        a = json.loads(path.read_text())
        if a.get('run_id') == combo['run_id']:
            audits.append({k: a.get(k) for k in ('started_at', 'finished_at', 'launcher_status', 'runtime', 'slurm_job_id', 'slurm_array_task_id', 'hostname', 'held_out_test_loaded')})
    item['launcher_audits'] = audits
    report['runs'].append(item)
print(json.dumps(report, indent=2))
PY
for f in "$ROOT"/logs/slurm-*.out; do
  [ -f "$f" ] || continue
  printf '\nLOG %s\n' "$f"
  tail -n 10 "$f"
done
for f in "$ROOT"/logs/slurm-*.err; do
  [ -s "$f" ] || continue
  printf '\nSTDERR %s\n' "$f"
  tail -n 12 "$f"
done
