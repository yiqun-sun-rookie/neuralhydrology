#!/bin/bash
# ID29 seq=165: inspect preserved all-531 audit bytes and the failed wrapper log.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PARTIAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_training_data_port_all531.preparing-202506"
SLURM="$PARTIAL/run_author_v13_training_data_port_all531.slurm"

echo "=== PRESERVED FILE HASHES ==="
test -d "$PARTIAL"
sha256sum "$PARTIAL"/*

echo "=== SUBMITTED SLURM SCRIPT ==="
cat "$SLURM"

echo "=== AUDIT STANDARD OUTPUT ==="
cat "$PARTIAL/audit_stdout.json"

echo "=== AUDIT JSON ==="
cat "$PARTIAL/audit.json"

echo "=== RESOLVED SLURM LOGS ==="
while IFS= read -r TEMPLATE; do
  PATH_VALUE=${TEMPLATE//%j/202506}
  PATH_VALUE=${PATH_VALUE//%A/202506}
  PATH_VALUE=${PATH_VALUE//%x/N22-data-port-531}
  if [[ "$PATH_VALUE" != /* ]]; then
    PATH_VALUE="$ROOT/$PATH_VALUE"
  fi
  printf '%s\n' "$PATH_VALUE"
  if test -f "$PATH_VALUE"; then
    stat --printf='%n|%s bytes|%y\n' "$PATH_VALUE"
    tail -n 400 "$PATH_VALUE"
  fi
done < <(sed -n -E 's/^#SBATCH --(output|error)=//p' "$SLURM")

find "$ROOT/logs" -maxdepth 4 -type f -name '*202506*' -print 2>/dev/null || true
exit 0

DIAG_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"

echo "=== JOB RECORD ==="
RECORD=$(scontrol show job -dd -o 202506 2>&1 || true)
printf '%s\n' "$RECORD"
sacct -n -P -j 202506 \
  --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList,WorkDir,SubmitLine,AllocTRES,ReqTRES || true
seff 202506 || true

field() {
  printf '%s\n' "$RECORD" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -n 1
}

echo "=== STANDARD OUTPUT AND ERROR ==="
for KEY in StdOut StdErr Command; do
  VALUE=$(field "$KEY")
  printf '%s=%s\n' "$KEY" "$VALUE"
  if test -n "$VALUE" && test -f "$VALUE"; then
    stat --printf='%n|%s bytes|%y\n' "$VALUE"
    tail -n 300 "$VALUE"
  fi
done

echo "=== RECENT DIAGNOSTIC FILES ==="
if test -d "$DIAG_ROOT"; then
  find "$DIAG_ROOT" -maxdepth 3 -type f -mmin -180 \
    -printf '%T@|%s|%p\n' | sort -n | tail -n 100
  find "$DIAG_ROOT" -maxdepth 2 -type d \
    \( -name '*training_data_port*' -o -name '.*training_data_port*' \) -print
fi
exit 0

JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315,202506,202507
DATA_FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_training_data_port_all531"
MASK_FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_warmup_isolation_all531"

echo "=== LIVE PROGRESS AND WALLTIME PROJECTION ==="
python - <<'PY'
import json
from pathlib import Path
import re
import subprocess

parents = '202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315,202506,202507'
running = subprocess.run(
    ['squeue', '-h', '-j', parents, '-t', 'RUNNING', '-o', '%i'],
    check=True,
    capture_output=True,
    text=True,
).stdout.split()
ansi = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
epoch_pattern = re.compile(r'# Epoch\s+(\d+):\s*(\d+)%\|.*?\|\s*(\d+)/(\d+)')
generic_pattern = re.compile(r'(?<!Epoch\s)(\d+)%\|.*?\|\s*(\d+)/(\d+)')

def seconds(value):
    days = 0
    if '-' in value:
        day_text, value = value.split('-', 1)
        days = int(day_text)
    fields = [int(item) for item in value.split(':')]
    if len(fields) == 3:
        hours, minutes, secs = fields
    elif len(fields) == 2:
        hours, minutes, secs = 0, fields[0], fields[1]
    else:
        raise ValueError(value)
    return days * 86400 + hours * 3600 + minutes * 60 + secs

for job in sorted(running):
    record = subprocess.run(
        ['scontrol', 'show', 'job', '-o', job],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    fields = dict(token.split('=', 1) for token in record.split() if '=' in token)
    stdout = Path(fields['StdOut'])
    payload = {
        'job': job,
        'name': fields['JobName'],
        'runtime': fields['RunTime'],
        'time_limit': fields['TimeLimit'],
        'stdout_exists': stdout.is_file(),
    }
    if not stdout.is_file():
        print(json.dumps(payload, sort_keys=True))
        continue
    size = stdout.stat().st_size
    with stdout.open('rb') as handle:
        handle.seek(max(0, size - 4 * 1024 * 1024))
        tail = ansi.sub('', handle.read().decode('utf-8', errors='replace')).replace('\r', '\n')
    epochs = list(epoch_pattern.finditer(tail))
    generic = list(generic_pattern.finditer(tail))
    payload['stdout_bytes'] = size
    if epochs:
        epoch, _, step, total = map(int, epochs[-1].groups())
        fraction = ((epoch - 1) + step / total) / 30
        projected = seconds(fields['RunTime']) / fraction if fraction > 0 else None
        limit = seconds(fields['TimeLimit'])
        payload.update({
            'epoch': epoch,
            'epoch_step': step,
            'epoch_total_steps': total,
            'thirty_epoch_fraction': round(fraction, 6),
            'conservative_projected_total_hours': round(projected / 3600, 2),
            'projected_slack_hours': round((limit - projected) / 3600, 2),
            'time_limit_risk': projected > limit,
        })
    elif generic:
        percent, step, total = map(int, generic[-1].groups())
        payload.update({
            'last_generic_percent': percent,
            'last_generic_step': step,
            'last_generic_total': total,
        })
    else:
        lines = [line.strip()[:300] for line in tail.splitlines() if line.strip()]
        payload['last_nonempty_line'] = lines[-1] if lines else ''
    print(json.dumps(payload, sort_keys=True))
PY

echo "=== REGISTERED COMPLETE-ROLE COUNTS ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python - <<'PY'
from collections import Counter
import json
from pathlib import Path
import sys

import pandas as pd

root = Path('/data1/home/sunyiq/nearing2022_da')
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from aggregate_registered_results import _registered_run
from prepare_evaluation_run import resolve_source_run
from verify_registered_closure import _metrics_path

registry_root = root / 'src/29_nearing2022_da_ar/registry'
training = pd.read_csv(registry_root / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry_root / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyper = pd.read_csv(registry_root / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str)

def complete(paths):
    return all(path.is_file() for path in paths)

training_done = Counter()
for _, row in training.iterrows():
    try:
        run = resolve_source_run(root, training, row['exp_id'])
        if complete([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log',
                     run / 'train_data/train_data_scaler.yml']):
            training_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

evaluation_done = Counter()
for _, row in evaluations.iterrows():
    try:
        run = _registered_run(root, training, row)
        result = run / row['result_file']
        reference = resolve_source_run(root, training, row['reference_exp_id']) / 'test/model_epoch030/test_results.p'
        if complete([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result,
                     _metrics_path(result), reference, _metrics_path(reference)]):
            evaluation_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

hyper_done = 0
for _, row in hyper.iterrows():
    try:
        run = Path(row['run_dir'])
        run = run if run.is_absolute() else root / run
        result = run / row['result_file']
        reference = resolve_source_run(root, training, row['source_exp_id']) / 'test/model_epoch030/test_results.p'
        if complete([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result,
                     _metrics_path(result), reference, _metrics_path(reference)]):
            hyper_done += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

print(json.dumps({
    'training_complete': sum(training_done.values()),
    'training_total': len(training),
    'training_by_family': dict(sorted(training_done.items())),
    'evaluation_complete': sum(evaluation_done.values()),
    'evaluation_total': len(evaluations),
    'evaluation_by_family': dict(sorted(evaluation_done.items())),
    'hyperparameter_complete': hyper_done,
    'hyperparameter_total': len(hyper),
}, sort_keys=True))
PY

echo "=== ALL-531 TRAINING-DATA-PORT DIAGNOSTIC ==="
sacct -n -P -j 202506 --format=JobID,State,ExitCode,Elapsed,Start,End,NodeList
if test -d "$DATA_FINAL"; then
  test -f "$DATA_FINAL/audit.json"
  test -f "$DATA_FINAL/diagnostic_receipt.json"
  sha256sum "$DATA_FINAL/audit.json" "$DATA_FINAL/diagnostic_receipt.json" \
    "$DATA_FINAL/audit_training_data_port.py" \
    "$DATA_FINAL/run_author_v13_training_data_port_all531.slurm"
  cat "$DATA_FINAL/diagnostic_receipt.json"
  python - "$DATA_FINAL/audit.json" <<'PY'
import json
from pathlib import Path
import sys

audit = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
print(json.dumps({
    'scope': audit['scope'],
    'source': audit['source'],
    'inputs': audit['inputs'],
    'target_scaler': audit['target_scaler'],
    'raw_targets_after_inverse_scaling': audit['raw_targets_after_inverse_scaling'],
    'per_basin_target_standard_deviation': {
        'basins_exact': audit['per_basin_target_standard_deviation']['basins_exact'],
        'basins_different': audit['per_basin_target_standard_deviation']['basins_different'],
        'absolute_difference_quantiles': audit['per_basin_target_standard_deviation']['absolute_difference_quantiles'],
    },
    'conclusion': audit['conclusion'],
}, sort_keys=True))
PY
else
  echo "data_diagnostic_final_absent"
fi

echo "=== ALL-531 SINGLE-MASK ISOLATION ==="
sacct -n -P -j 202507 --format=JobID,State,ExitCode,Elapsed,Start,End,NodeList
if test -d "$MASK_FINAL"; then
  test -f "$MASK_FINAL/audit.json"
  test -f "$MASK_FINAL/diagnostic_receipt.json"
  sha256sum "$MASK_FINAL/audit.json" "$MASK_FINAL/diagnostic_receipt.json" \
    "$MASK_FINAL/audit_training_data_port.py" "$MASK_FINAL/audit_warmup_target_isolation.py" \
    "$MASK_FINAL/warmup_target_paired_retraining_protocol.json" \
    "$MASK_FINAL/run_author_v13_warmup_isolation_all531.slurm"
  cat "$MASK_FINAL/diagnostic_receipt.json"
  python - "$MASK_FINAL/audit.json" <<'PY'
import json
from pathlib import Path
import sys

audit = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
print(json.dumps({
    'scope': audit['scope'],
    'author_vs_current_masked': audit['author_vs_current_masked'],
    'one_factor_contract': audit['one_factor_contract'],
    'conclusion': audit['conclusion'],
}, sort_keys=True))
PY
else
  echo "mask_isolation_final_absent"
fi

echo "=== ACTIVE MAIN JOBS AND FAILURE STATES ==="
squeue -h -j "$JOBS" -o '%i|%T|%M|%l|%R|%j' | sort
FAILURES=$(sacct -n -P -j "$JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

echo "=== REGISTERED ARTIFACT SAFETY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
