#!/bin/bash
# ID29 seq=185: refresh matrix, replacement gates, and deployed verifier payload.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
MAIN_JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315
REPAIR_JOBS=202510,202511
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
DATA_V2="$DIAGNOSTIC_ROOT/author_v13_training_data_port_all531_v2"
MASK_V2="$DIAGNOSTIC_ROOT/author_v13_warmup_isolation_all531_v2"
SUBMISSION_RECEIPT="$DIAGNOSTIC_ROOT/warmup_target_repair_submission_01.json"

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

echo "=== LIVE DOWNSTREAM DEPENDENCY GRAPH ==="
for job in 202238 202229 202230 202280 202281 202294 202315; do
  if ! record=$(scontrol show job -o "$job" 2>&1); then
    printf '%s|ABSENT_OR_RETIRED|||%s\n' "$job" "$record"
    continue
  fi
  state=$(sed -n 's/.*JobState=\([^ ]*\).*/\1/p' <<<"$record")
  reason=$(sed -n 's/.*Reason=\([^ ]*\).*/\1/p' <<<"$record")
  dependency=$(sed -n 's/.*Dependency=\([^ ]*\).*/\1/p' <<<"$record")
  command=$(sed -n 's/.*Command=\([^ ]*\).*/\1/p' <<<"$record")
  printf '%s|%s|%s|%s|%s\n' "$job" "$state" "$reason" "$dependency" "$command"
done

dep_202238=$(scontrol show job -o 202238 | sed -n 's/.*Dependency=\([^ ]*\).*/\1/p')
dep_202229=$(scontrol show job -o 202229 | sed -n 's/.*Dependency=\([^ ]*\).*/\1/p')
dep_202230=$(scontrol show job -o 202230 | sed -n 's/.*Dependency=\([^ ]*\).*/\1/p')
grep -q 'afterok:202216' <<<"$dep_202238"
for required in 202222 202226 202216 202238 202227; do grep -q "$required" <<<"$dep_202229"; done
for required in 202228 202238; do grep -q "$required" <<<"$dep_202230"; done
echo "dependency_graph_assertions=passed"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "=== REGISTERED COMPLETE-ROLE COUNTS ==="
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

registry = root / 'src/29_nearing2022_da_ar/registry'
training = pd.read_csv(registry / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyper = pd.read_csv(registry / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str)


def complete(paths):
    return all(path.is_file() for path in paths)


training_done = Counter()
for _, row in training.iterrows():
    try:
        run = resolve_source_run(root, training, row['exp_id'])
        if complete([
            run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log',
            run / 'train_data/train_data_scaler.yml',
        ]):
            training_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

evaluation_done = Counter()
for _, row in evaluations.iterrows():
    try:
        run = _registered_run(root, training, row)
        result = run / row['result_file']
        reference_run = resolve_source_run(root, training, row['reference_exp_id'])
        reference = reference_run / 'test/model_epoch030/test_results.p'
        if complete([
            run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result,
            _metrics_path(result), reference, _metrics_path(reference),
        ]):
            evaluation_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

hyper_done = 0
for _, row in hyper.iterrows():
    try:
        run = Path(row['run_dir'])
        run = run if run.is_absolute() else root / run
        result = run / row['result_file']
        reference_run = resolve_source_run(root, training, row['source_exp_id'])
        reference = reference_run / 'test/model_epoch030/test_results.p'
        if complete([
            run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result,
            _metrics_path(result), reference, _metrics_path(reference),
        ]):
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

echo "=== SERVER OUTPUT-TARGET AUDIT ==="
python - <<'PY'
import hashlib
import json
from pathlib import Path

import pandas as pd
import yaml

root = Path('/data1/home/sunyiq/nearing2022_da')
registry = root / 'src/29_nearing2022_da_ar/registry'
training_path = registry / 'experiment_registry.csv'
evaluation_path = registry / 'evaluation_registry.csv'
hyper_path = registry / 'assimilation_hyperparameter_registry.csv'
training = pd.read_csv(training_path, keep_default_na=False, dtype=str).set_index('exp_id')
evaluations = pd.read_csv(evaluation_path, keep_default_na=False, dtype=str)
hyper = pd.read_csv(hyper_path, keep_default_na=False, dtype=str)


def file_record(path):
    payload = path.read_bytes()
    return {'path': str(path.relative_to(root)), 'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}


literal_dirs = evaluations['run_dir'].astype(str).str.replace('\\', '/', regex=False).tolist()
direct = evaluations[evaluations['family'].isin({'basin_simulation', 'basin_autoregression'})]
source_rows = training.loc[direct['source_exp_id']]
runtime_patterns = []
for row in source_rows.itertuples():
    config = yaml.safe_load((root / row.config_path).read_text(encoding='utf-8'))
    runtime_patterns.append(
        str(config['run_dir']).replace('\\', '/').rstrip('/') + '/' + str(config['experiment_name']) + '_*_ep30'
    )

logical_evaluation_targets = []
for row in evaluations.itertuples():
    if row.family in {'basin_simulation', 'basin_autoregression'}:
        value = str(training.loc[row.source_exp_id, 'run_dir'])
    else:
        value = str(row.run_dir)
    logical_evaluation_targets.append(value.replace('\\', '/'))
logical_all_targets = logical_evaluation_targets + hyper['run_dir'].astype(str).str.replace('\\', '/', regex=False).tolist()

payload = {
    'registries': [file_record(training_path), file_record(evaluation_path), file_record(hyper_path)],
    'training_rows': len(training),
    'training_unique_registered_run_dirs': training['run_dir'].nunique(),
    'evaluation_rows': len(evaluations),
    'evaluation_literal_unique_run_dirs': len(set(literal_dirs)),
    'evaluation_literal_duplicate_groups': sum(count > 1 for count in pd.Series(literal_dirs).value_counts()),
    'direct_basin_rows': len(direct),
    'direct_unique_source_exp_ids': direct['source_exp_id'].nunique(),
    'direct_unique_source_config_paths': source_rows['config_path'].nunique(),
    'direct_unique_registered_source_run_dirs': source_rows['run_dir'].nunique(),
    'direct_unique_runtime_patterns': len(set(runtime_patterns)),
    'resolved_evaluation_targets': len(logical_evaluation_targets),
    'resolved_unique_evaluation_targets': len(set(logical_evaluation_targets)),
    'resolved_casefold_unique_evaluation_targets': len({item.casefold() for item in logical_evaluation_targets}),
    'evaluation_plus_hyperparameter_targets': len(logical_all_targets),
    'unique_evaluation_plus_hyperparameter_targets': len(set(logical_all_targets)),
    'casefold_unique_evaluation_plus_hyperparameter_targets': len({item.casefold() for item in logical_all_targets}),
}
assert payload['training_rows'] == payload['training_unique_registered_run_dirs'] == 46
assert payload['evaluation_rows'] == 180
assert payload['evaluation_literal_unique_run_dirs'] == 162
assert payload['evaluation_literal_duplicate_groups'] == 2
assert payload['direct_basin_rows'] == 20
assert payload['direct_unique_source_exp_ids'] == 20
assert payload['direct_unique_source_config_paths'] == 20
assert payload['direct_unique_registered_source_run_dirs'] == 20
assert payload['direct_unique_runtime_patterns'] == 20
assert payload['resolved_evaluation_targets'] == payload['resolved_unique_evaluation_targets'] == 180
assert payload['resolved_casefold_unique_evaluation_targets'] == 180
assert payload['evaluation_plus_hyperparameter_targets'] == payload['unique_evaluation_plus_hyperparameter_targets'] == 840
assert payload['casefold_unique_evaluation_plus_hyperparameter_targets'] == 840
expected_hashes = {
    'src/29_nearing2022_da_ar/registry/experiment_registry.csv':
        '6366d468d671a2af39c2a136b984ca4ee9ebfc1106618b945287bdaabe629d64',
    'src/29_nearing2022_da_ar/registry/evaluation_registry.csv':
        '37b312dbd362399a9771f2233d1e1139ea25d5339d1bbc7a806fa75be30b9215',
    'src/29_nearing2022_da_ar/registry/assimilation_hyperparameter_registry.csv':
        '7cb7f10ce13c41c1b064148b27a707ccaab56f87fa40c289d6833bc7c57b09a7',
}
assert {row['path']: row['sha256'] for row in payload['registries']} == expected_hashes
print(json.dumps(payload, sort_keys=True))
PY

echo "=== DIRECT-EVALUATION JOB PAYLOAD ==="
python - <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess

root = Path('/data1/home/sunyiq/nearing2022_da')
live_script = root / 'src/29_nearing2022_da_ar/hpc/run_registered_evaluation_array.slurm'
live_prepare = root / 'src/29_nearing2022_da_ar/scripts/prepare_evaluation_run.py'
record = subprocess.run(
    ['scontrol', 'show', 'job', '-dd', '-o', '202238'], check=True, capture_output=True, text=True,
).stdout.strip()
record_fields = dict(token.split('=', 1) for token in record.split() if '=' in token)
spooled = subprocess.run(
    ['scontrol', 'write', 'batch_script', '202238', '/dev/stdout'], capture_output=True, text=True,
)
markers = ['prepare_evaluation_run.py', 'SKIPPED_COMPLETED', 'python -m neuralhydrology.nh_run evaluate']
payload = {
    'job_id': '202238',
    'job_command': record_fields.get('Command'),
    'job_work_dir': record_fields.get('WorkDir'),
    'job_dependency': record_fields.get('Dependency'),
    'job_environment': record_fields.get('Environment'),
    'job_record_contains_expected_command': str(live_script) in record,
    'job_record_contains_expected_batch_file': 'basin_direct_evaluation_batch.txt' in record,
    'spooled_script_retrieval_returncode': spooled.returncode,
    'spooled_script_bytes': len(spooled.stdout.encode()),
    'spooled_script_sha256': hashlib.sha256(spooled.stdout.encode()).hexdigest() if spooled.stdout else None,
    'spooled_script_markers': {marker: marker in spooled.stdout for marker in markers},
    'live_script_sha256': hashlib.sha256(live_script.read_bytes()).hexdigest(),
    'live_prepare_sha256': hashlib.sha256(live_prepare.read_bytes()).hexdigest(),
}
assert payload['live_prepare_sha256'] == '6e47896c2b3011fe8e93a561f7545397d5a4ddee70b09b38a520f08530646ccf'
print(json.dumps(payload, sort_keys=True))
if spooled.returncode != 0:
    print(json.dumps({'spooled_script_retrieval_stderr': spooled.stderr.strip()}, sort_keys=True))
PY

echo "=== LIVE MAIN PROGRESS ==="
python - <<'PY'
import json
from pathlib import Path
import re
import subprocess

parents = '202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315'
running = subprocess.run(
    ['squeue', '-h', '-j', parents, '-t', 'RUNNING', '-o', '%i'],
    check=True, capture_output=True, text=True,
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
    else:
        hours, minutes, secs = 0, fields[0], fields[1]
    return days * 86400 + hours * 3600 + minutes * 60 + secs


for job in sorted(running):
    record = subprocess.run(
        ['scontrol', 'show', 'job', '-o', job], check=True, capture_output=True, text=True,
    ).stdout.strip()
    fields = dict(token.split('=', 1) for token in record.split() if '=' in token)
    stdout = Path(fields['StdOut'])
    payload = {
        'job': job, 'name': fields['JobName'], 'runtime': fields['RunTime'],
        'time_limit': fields['TimeLimit'], 'stdout_exists': stdout.is_file(),
    }
    if stdout.is_file():
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
                'epoch': epoch, 'epoch_step': step, 'epoch_total_steps': total,
                'thirty_epoch_fraction': round(fraction, 6),
                'projected_total_hours': round(projected / 3600, 2),
                'projected_slack_hours': round((limit - projected) / 3600, 2),
                'time_limit_risk': projected > limit,
            })
        elif generic:
            percent, step, total = map(int, generic[-1].groups())
            payload.update({'percent': percent, 'step': step, 'total': total})
    print(json.dumps(payload, sort_keys=True))
PY

echo "=== REPLACEMENT AUDIT STATES ==="
sacct -n -X -P -j "$REPAIR_JOBS" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End,NodeList
squeue -h -j "$REPAIR_JOBS" -o '%i|%j|%T|%M|%R|%E' | sort

echo "=== REPLACEMENT RECEIPT AND OUTPUTS ==="
test -f "$SUBMISSION_RECEIPT"
test "$(sha256sum "$SUBMISSION_RECEIPT" | awk '{print $1}')" = \
  18e6aeeee3321427d0f851d68d2cbbfb02f8d13e477f6f96dd5f22eed1d4d2a1
sha256sum "$SUBMISSION_RECEIPT"
find "$DIAGNOSTIC_ROOT" -maxdepth 1 -mindepth 1 \
  \( -name 'author_v13_training_data_port_all531_v2*' -o -name 'author_v13_warmup_isolation_all531_v2*' \) \
  -printf '%f|%y\n' | sort

for final in "$DATA_V2" "$MASK_V2"; do
  if test -d "$final"; then
    test -f "$final/audit.json"
    test -f "$final/diagnostic_receipt.json"
    sha256sum "$final/audit.json" "$final/diagnostic_receipt.json"
    cat "$final/audit.json"
    cat "$final/diagnostic_receipt.json"
  else
    echo "absent|$final"
  fi
done

echo "=== REPLACEMENT VERIFIER STRICT PREREQUISITES ==="
SOURCE_RUN="$ROOT/results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_seed0_2026_0808_1648_ep30"
STRICT_MISMATCHES=0
while IFS='|' read -r label expected path; do
  test -n "$label" || continue
  if ! test -f "$path"; then
    echo "$label|ABSENT|$expected|$path"
    STRICT_MISMATCHES=$((STRICT_MISMATCHES + 1))
    continue
  fi
  actual=$(sha256sum "$path" | awk '{print $1}')
  bytes=$(stat -c '%s' "$path")
  status=UNBOUND
  if test "$expected" != '-'; then
    if test "$actual" = "$expected"; then
      status=MATCH
    else
      status=MISMATCH
      STRICT_MISMATCHES=$((STRICT_MISMATCHES + 1))
    fi
  fi
  echo "$label|$status|$actual|$bytes|$path"
done <<EOF
deployed_protocol|16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1|$DIAGNOSTIC_ROOT/warmup_target_paired_retraining_protocol.json
deployed_amendment|a21bae28a26f5797e96232628fdc139f5ffd1e54e31ee2032a7805acb0785ef5|$DIAGNOSTIC_ROOT/warmup_target_paired_retraining_protocol_amendment_01.json
submission_receipt|18e6aeeee3321427d0f851d68d2cbbfb02f8d13e477f6f96dd5f22eed1d4d2a1|$SUBMISSION_RECEIPT
failed_audit|3f5fe1e597a2d8cee36dffac4426a178075d8828eae560c585fe7727d2a4aa30|$DIAGNOSTIC_ROOT/author_v13_training_data_port_all531.preparing-202506/audit.json
failed_stdout|a577a8ec870a4f2a100643b3d6cfc49a29a00d19384bee888590b9cee3112336|$DIAGNOSTIC_ROOT/author_v13_training_data_port_all531.preparing-202506/audit_stdout.json
version1_audit|5f7d49c4899aeb0ffb1d097cffd98cfe86393f86b5849a153d3074094744eb85|$ROOT/src/29_nearing2022_da_ar/scripts/audit_training_data_port.py
version2_audit|51b9091c928a8b514f0be6e81ab5afd304bda654e3dc63a6cb27746e3dee3233|$ROOT/src/29_nearing2022_da_ar/scripts/audit_training_data_port_v2.py
isolation_audit|9f898a80aafb4e207bb56fd095125e9d5d092ec8c96af4d6010bdaeb36a27f8c|$ROOT/src/29_nearing2022_da_ar/scripts/audit_warmup_target_isolation.py
data_wrapper|7805e78942a9d512075deb1f546a230d4fe20f04a7efd837a8507ada9e4a493e|$ROOT/src/29_nearing2022_da_ar/hpc/run_author_v13_training_data_port_all531_v2.slurm
mask_wrapper|9d8d2c890e6ec8a28be30e674ea05c3c90a8926ba0e4e80bf088386879127053|$ROOT/src/29_nearing2022_da_ar/hpc/run_author_v13_warmup_isolation_all531_v2.slurm
frozen_config|729985706faeb8c45480d3c485dbad72ae51eec94dff69b5c8964e2036591b1a|$ROOT/src/29_nearing2022_da_ar/configs/full_reproduction/time_split/autoregression/lead_1_holdout_0.0_seed_0.yml
frozen_basins|cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85|$ROOT/src/29_nearing2022_da_ar/basin_lists/531_basin_list.txt
training_registry|6366d468d671a2af39c2a136b984ca4ee9ebfc1106618b945287bdaabe629d64|$ROOT/src/29_nearing2022_da_ar/registry/experiment_registry.csv
evaluation_registry|37b312dbd362399a9771f2233d1e1139ea25d5339d1bbc7a806fa75be30b9215|$ROOT/src/29_nearing2022_da_ar/registry/evaluation_registry.csv
basedataset|4658816ea3110a1c2efcf54c3dcf00d5c0982459dca4f7ac985beb983b12df0d|$ROOT/neuralhydrology/datasetzoo/basedataset.py
registered_checkpoint|c2a6f260d555e323650103a84bc066d591fc8cc3e6bf8142a89f9ccd7f64661b|$SOURCE_RUN/model_epoch030.pt
registered_source_config|-|$SOURCE_RUN/config.yml
registered_source_scaler|add1a777647f92f1aa7a8ad039e3d406d32f05c21f30c685a14736d22f45a5d4|$SOURCE_RUN/train_data/train_data_scaler.yml
EOF
echo "strict_prerequisite_mismatches=$STRICT_MISMATCHES"
test "$STRICT_MISMATCHES" -eq 0

echo "=== FUTURE VERIFIER PAYLOAD INVENTORY ==="
while IFS='|' read -r label expected path; do
  test -n "$label" || continue
  if test -f "$path"; then
    actual=$(sha256sum "$path" | awk '{print $1}')
    bytes=$(stat -c '%s' "$path")
    if test "$actual" = "$expected"; then status=MATCH; else status=STALE_OR_DIFFERENT; fi
    echo "$label|$status|$actual|$bytes|$path"
  else
    echo "$label|ABSENT|$expected|$path"
  fi
done <<EOF
source_protocol|16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_paired_retraining_protocol.json
source_amendment|a21bae28a26f5797e96232628fdc139f5ffd1e54e31ee2032a7805acb0785ef5|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_paired_retraining_protocol_amendment_01.json
replacement_verifier|0bcabc96f9e702f2317464f1f0123c29d49d5f7f0f972a10ea3e01bbf18fe987|$ROOT/src/29_nearing2022_da_ar/scripts/verify_warmup_target_replacement_chain.py
replacement_verifier_test|2da179cb1ef02b0697472fd273bd61ffad98ecb5790e5b5f2dce6032e478dad6|$ROOT/test/test_nearing2022_replacement_chain_verifier.py
reproduction_contract_test|fe41d31b546e2839c2bbc4524a6109ba818f68124327f1f5db515eeff762945c|$ROOT/test/test_nearing2022_reproduction_contract.py
comparison_register|06927b7472a5f60134da7ccb2a91def112386421da5baf7819b8687917b8e9c8|$ROOT/results/29_nearing2022_da_ar/formal_closure/reproduction_comparison_register.json
replacement_verifier_preflight|80bf711779dcef12b991be7b53359dfcdc550e3fbf049720ec5bc24b01620b0f|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_replacement_independent_verifier_preflight_20260811.json
replacement_verifier_prerequisites|e4211d680611e34d85c9b93ebcb8c90f5b05fa7425e0e6f0830ad6971260fa8f|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_replacement_verifier_prerequisite_audit_20260811.json
replacement_verifier_deployment|d469d2b135c533ac7bfb0433cf6f3ab52fc2e4dfb4e685e229dfbe48c8ef1b40|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_replacement_verifier_payload_deployment_20260811.json
EOF

while IFS='|' read -r expected path; do
  test "$(sha256sum "$path" | awk '{print $1}')" = "$expected"
done <<EOF
16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_paired_retraining_protocol.json
a21bae28a26f5797e96232628fdc139f5ffd1e54e31ee2032a7805acb0785ef5|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_paired_retraining_protocol_amendment_01.json
0bcabc96f9e702f2317464f1f0123c29d49d5f7f0f972a10ea3e01bbf18fe987|$ROOT/src/29_nearing2022_da_ar/scripts/verify_warmup_target_replacement_chain.py
2da179cb1ef02b0697472fd273bd61ffad98ecb5790e5b5f2dce6032e478dad6|$ROOT/test/test_nearing2022_replacement_chain_verifier.py
80bf711779dcef12b991be7b53359dfcdc550e3fbf049720ec5bc24b01620b0f|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_replacement_independent_verifier_preflight_20260811.json
e4211d680611e34d85c9b93ebcb8c90f5b05fa7425e0e6f0830ad6971260fa8f|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_replacement_verifier_prerequisite_audit_20260811.json
d469d2b135c533ac7bfb0433cf6f3ab52fc2e4dfb4e685e229dfbe48c8ef1b40|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_replacement_verifier_payload_deployment_20260811.json
EOF
echo "deployed_verifier_payload_hashes=passed"

echo "=== MAIN JOB STATES AND FAILURE GATE ==="
squeue -h -j "$MAIN_JOBS" -o '%i|%T|%M|%l|%R|%j' | sort
MAIN_FAILURES=$(sacct -n -X -P -j "$MAIN_JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$MAIN_FAILURES"
test -z "$MAIN_FAILURES"

echo "=== FROZEN SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
