#!/bin/bash
# ID29 seq=142: correct the executable-AST comparison by excluding docstrings as well as annotations.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== BOUNDED PROGRESS AND WALLTIME PROJECTION ==="
python - <<'PY'
import json
from pathlib import Path
import re
import subprocess

parents = '202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315'
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
    fields = {}
    for token in record.split():
        if '=' in token:
            key, value = token.split('=', 1)
            fields[key] = value
    stdout = Path(fields['StdOut'])
    size = stdout.stat().st_size
    with stdout.open('rb') as handle:
        handle.seek(max(0, size - 4 * 1024 * 1024))
        text = ansi.sub('', handle.read().decode('utf-8', errors='replace')).replace('\r', '\n')
    epochs = list(epoch_pattern.finditer(text))
    generic = list(generic_pattern.finditer(text))
    payload = {
        'job': job,
        'name': fields['JobName'],
        'runtime': fields['RunTime'],
        'time_limit': fields['TimeLimit'],
        'stdout_bytes': size,
    }
    if epochs:
        match = epochs[-1]
        epoch, percent, step, total = map(int, match.groups())
        fraction = ((epoch - 1) + step / total) / 30
        runtime_seconds = seconds(fields['RunTime'])
        limit_seconds = seconds(fields['TimeLimit'])
        projected_seconds = runtime_seconds / fraction if fraction > 0 else None
        payload.update({
            'epoch': epoch,
            'epoch_step': step,
            'epoch_total_steps': total,
            'thirty_epoch_fraction': round(fraction, 6),
            'conservative_projected_total_hours': round(projected_seconds / 3600, 2),
            'projected_slack_hours': round((limit_seconds - projected_seconds) / 3600, 2),
            'time_limit_risk': projected_seconds > limit_seconds,
        })
    elif generic:
        percent, step, total = map(int, generic[-1].groups())
        payload.update({'last_generic_percent': percent, 'last_generic_step': step, 'last_generic_total': total})
    else:
        lines = [line.strip()[:300] for line in text.splitlines() if line.strip()]
        payload['last_nonempty_line'] = lines[-1] if lines else ''
    print(json.dumps(payload, sort_keys=True))
PY

echo "=== ACTIVE MAIN JOBS ==="
squeue -h -j "$JOBS" -o '%i|%T|%M|%l|%R|%j' | sort

echo "=== BASIN TRAINING TASKS ==="
sacct -n -P -j 202216 --format=JobID,State,ExitCode,Elapsed,Start,End,NodeList | \
  awk -F'|' '$1 !~ /\./ && $1 ~ /^202216_[0-9]+$/ {print}' | sort

echo "=== ACTIVE FAILURE STATES ==="
FAILURES=$(sacct -n -P -j "$JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

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

echo "=== PARTIAL NUMERICAL AUDIT OF COMPLETE EVALUATIONS ==="
python - <<'PY'
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys

import pandas as pd

root = Path('/data1/home/sunyiq/nearing2022_da')
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from aggregate_registered_results import (  # noqa: E402
    _author_time_value,
    _read_registry,
    _registered_run,
    load_legacy_pandas_pickle,
)
from prepare_evaluation_run import resolve_source_run  # noqa: E402
from score_reproduction_matrix import METRICS, _load_pickle, score_payloads  # noqa: E402
from verify_registered_closure import _metrics_path  # noqa: E402

registry_root = root / 'src/29_nearing2022_da_ar/registry'
reference_root = root / 'src/29_nearing2022_da_ar/reference'
training = _read_registry(registry_root / 'experiment_registry.csv', 'exp_id')
evaluations = _read_registry(registry_root / 'evaluation_registry.csv', 'eval_id')
author_path = reference_root / 'author_time_split_statistics.pkl'
acceptance_path = reference_root / 'reproduction_acceptance.json'
author = load_legacy_pandas_pickle(author_path)
acceptance = json.loads(acceptance_path.read_text(encoding='utf-8'))
tolerances = {key: float(value) for key, value in acceptance['absolute_difference_tolerance'].items()}
systematic = {
    key: float(value) for key, value in acceptance['median_signed_difference_tolerance'].items()
}

complete = []
for _, row in evaluations.iterrows():
    try:
        run = _registered_run(root, training, row)
        result = run / row['result_file']
        reference_run = resolve_source_run(root, training, row['reference_exp_id'])
        reference = reference_run / 'test/model_epoch030/test_results.p'
        roles = [
            run / 'config.yml',
            run / 'model_epoch030.pt',
            run / 'output.log',
            result,
            _metrics_path(result),
            reference,
            _metrics_path(reference),
        ]
        if all(path.is_file() for path in roles):
            complete.append((row, reference, result))
    except (FileNotFoundError, KeyError, ValueError):
        continue

reference_cache = {}
details = []
coordinate_rows = []
for row, reference_path, result_path in complete:
    if reference_path not in reference_cache:
        reference_cache[reference_path] = _load_pickle(reference_path)
    reference = reference_cache[reference_path]
    scores = score_payloads(reference, _load_pickle(result_path), expected_basins=len(reference))
    if len(scores) != 531 or scores['basin'].nunique() != 531:
        raise ValueError(f"{row['eval_id']} did not score exactly 531 unique basins")
    failures = []
    nse = None
    nse_author = None
    nse_difference = None
    max_abs_difference = 0.0
    for metric in METRICS:
        reproduction = float(scores[metric].median())
        author_value = _author_time_value(author, row, metric)
        difference = reproduction - author_value
        within = abs(difference) <= tolerances[metric] + 1e-12
        details.append({
            'eval_id': row['eval_id'],
            'family': row['family'],
            'metric': metric,
            'difference': difference,
            'within_tolerance': within,
        })
        if not within:
            failures.append(metric)
        max_abs_difference = max(max_abs_difference, abs(difference))
        if metric == 'NSE':
            nse = reproduction
            nse_author = author_value
            nse_difference = difference
    coordinate_rows.append({
        'eval_id': row['eval_id'],
        'family': row['family'],
        'lead': int(row['lead']),
        'train_holdout': float(row['train_holdout']) if row['train_holdout'] else None,
        'test_holdout': float(row['test_holdout']),
        'basins': len(scores),
        'nse': nse,
        'author_nse': nse_author,
        'nse_difference': nse_difference,
        'maximum_absolute_metric_difference': max_abs_difference,
        'failed_metrics': failures,
        'result_path': str(result_path.relative_to(root)),
        'reference_path': str(reference_path.relative_to(root)),
    })

frame = pd.DataFrame(details)
summary = {
    'complete_coordinates': len(complete),
    'complete_by_family': dict(sorted(Counter(row['family'] for row, _, _ in complete).items())),
    'comparison_rows': len(frame),
    'individual_tolerance_failures': int((~frame['within_tolerance']).sum()),
    'coordinates_with_failures': int(sum(bool(row['failed_metrics']) for row in coordinate_rows)),
    'author_statistics_sha256': hashlib.sha256(author_path.read_bytes()).hexdigest(),
    'acceptance_sha256': hashlib.sha256(acceptance_path.read_bytes()).hexdigest(),
    'scope': 'interim diagnostic only; the frozen final gate still requires all registered coordinates',
}
print(json.dumps(summary, sort_keys=True))
for metric in METRICS:
    values = frame.loc[frame['metric'] == metric]
    payload = {
        'metric': metric,
        'coordinates': len(values),
        'median_signed_difference': float(values['difference'].median()),
        'systematic_tolerance': systematic[metric],
        'partial_within_systematic_tolerance': bool(
            abs(float(values['difference'].median())) <= systematic[metric] + 1e-12
        ),
        'maximum_absolute_difference': float(values['difference'].abs().max()),
        'individual_failures': int((~values['within_tolerance']).sum()),
    }
    print(json.dumps(payload, sort_keys=True))
for payload in coordinate_rows:
    print(json.dumps(payload, sort_keys=True))
PY

echo "=== INDEPENDENT RAW TE100 NSE CONFIRMATION ==="
python - <<'PY'
import hashlib
import json
from pathlib import Path
import pickle
import sys

import numpy as np
import pandas as pd
import yaml

root = Path('/data1/home/sunyiq/nearing2022_da')
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from aggregate_registered_results import load_legacy_pandas_pickle  # noqa: E402
from prepare_evaluation_run import resolve_source_run  # noqa: E402

registry_root = root / 'src/29_nearing2022_da_ar/registry'
reference_root = root / 'src/29_nearing2022_da_ar/reference'
training = pd.read_csv(registry_root / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry_root / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
eval_id = 'N22-EVAL-TS-AR-L01-TR000-TE100-S0'
selected = evaluations.loc[evaluations['eval_id'] == eval_id]
if len(selected) != 1:
    raise ValueError(f'Expected one registry row for {eval_id}, found {len(selected)}')
row = selected.iloc[0]
if not (
    row['family'] == 'time_autoregression'
    and int(row['lead']) == 1
    and float(row['train_holdout']) == 0.0
    and float(row['test_holdout']) == 1.0
    and int(row['seed']) == 0
):
    raise ValueError('Frozen registry row does not match the intended TE100 coordinate')

candidate_run = root / row['run_dir']
source_run = resolve_source_run(root, training, row['source_exp_id'])
reference_run = resolve_source_run(root, training, row['reference_exp_id'])
candidate_result = candidate_run / row['result_file']
reference_result = reference_run / 'test/model_epoch030/test_results.p'
candidate_checkpoint = candidate_run / 'model_epoch030.pt'
source_checkpoint = source_run / 'model_epoch030.pt'
candidate_config_path = candidate_run / 'config.yml'
metrics_path = candidate_result.with_name('test_metrics.csv')

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

config = yaml.safe_load(candidate_config_path.read_text(encoding='utf-8'))
holdout = config['random_holdout_from_dynamic_features']
expected_holdout = {
    'QObs(mm/d)_shift1': {
        'missing_fraction': 1.0,
        'mean_missing_length': 5,
    }
}
if holdout != expected_holdout:
    raise ValueError(f'Unexpected TE100 holdout config: {holdout!r}')
if config['model'].lower() != 'arlstm' or int(config['seed']) != 0:
    raise ValueError('TE100 config does not use the registered ARLSTM and seed')
source_checkpoint_sha256 = digest(source_checkpoint)
candidate_checkpoint_sha256 = digest(candidate_checkpoint)
if candidate_checkpoint_sha256 != source_checkpoint_sha256:
    raise ValueError('Evaluation checkpoint bytes differ from the registered source checkpoint')

with reference_result.open('rb') as handle:
    reference = pickle.load(handle)
with candidate_result.open('rb') as handle:
    candidate = pickle.load(handle)
if set(reference) != set(candidate) or len(reference) != 531:
    raise ValueError('Reference and candidate basin sets are not the same 531 basins')

def extract(dataset, variable):
    values = np.asarray(dataset[variable].values)
    if values.ndim == 2 and values.shape[1] == 1:
        values = values[:, 0]
    elif values.ndim != 1:
        raise ValueError(f'Unexpected shape for {variable}: {values.shape}')
    dates = np.asarray(dataset['date'].values)
    return pd.Series(values.astype(float), index=pd.DatetimeIndex(dates))

nse_values = []
common_counts = []
for basin in sorted(reference):
    reference_dataset = reference[basin]['1D']['xr']
    candidate_dataset = candidate[basin]['1D']['xr']
    obs = extract(reference_dataset, 'QObs(mm/d)_obs').rename('obs')
    sim = extract(candidate_dataset, 'QObs(mm/d)_sim').rename('sim')
    aligned = pd.concat([obs, sim], axis=1, join='inner').dropna()
    if aligned.index.has_duplicates or aligned.empty:
        raise ValueError(f'Invalid common-date record for basin {basin}')
    observed = aligned['obs'].to_numpy()
    simulated = aligned['sim'].to_numpy()
    denominator = float(np.sum((observed - np.mean(observed)) ** 2))
    if denominator == 0:
        nse = np.nan
    else:
        nse = 1.0 - float(np.sum((simulated - observed) ** 2)) / denominator
    nse_values.append(nse)
    common_counts.append(len(aligned))

manual_median_nse = float(np.nanmedian(np.asarray(nse_values, dtype=float)))
metrics = pd.read_csv(metrics_path)
metrics_median_nse = float(metrics['NSE'].median())
author_path = reference_root / 'author_time_split_statistics.pkl'
author = load_legacy_pandas_pickle(author_path)
author_median_nse = float(author[1]['NSE'][(0.0, 1.0, 1, 0)].median())
acceptance_path = reference_root / 'reproduction_acceptance.json'
acceptance = json.loads(acceptance_path.read_text(encoding='utf-8'))
tolerance = float(acceptance['absolute_difference_tolerance']['NSE'])
difference = manual_median_nse - author_median_nse
payload = {
    'eval_id': eval_id,
    'basins': len(nse_values),
    'minimum_common_dates': min(common_counts),
    'maximum_common_dates': max(common_counts),
    'manual_median_nse': manual_median_nse,
    'metrics_file_median_nse': metrics_median_nse,
    'manual_minus_metrics_file': manual_median_nse - metrics_median_nse,
    'author_median_nse': author_median_nse,
    'reproduction_minus_author': difference,
    'absolute_tolerance': tolerance,
    'within_absolute_tolerance': abs(difference) <= tolerance + 1e-12,
    'checkpoint_bytes_identical': True,
    'source_checkpoint_sha256': source_checkpoint_sha256,
    'candidate_checkpoint_sha256': candidate_checkpoint_sha256,
    'candidate_config_sha256': digest(candidate_config_path),
    'candidate_result_sha256': digest(candidate_result),
    'reference_result_sha256': digest(reference_result),
    'metrics_sha256': digest(metrics_path),
    'config_holdout': expected_holdout,
    'scoring_implementation': 'standalone NumPy NSE over common finite dates; no score_reproduction_matrix import',
}
print(json.dumps(payload, sort_keys=True))
PY

echo "=== AUTHOR VERSUS CURRENT RUNTIME BOUNDARY ==="
(
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python - <<'PY'
import ast
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import zipfile

import numpy
import pandas
import scipy
import torch
import xarray

root = Path('/data1/home/sunyiq/nearing2022_da')
archive = (
    root
    / 'results/29_nearing2022_da_ar/formal_closure/author_source_archives'
    / 'zenodo-7063259-grey-nearing-neuralhydrology-public-v.1.3.0.zip'
)
author_root = 'grey-nearing-neuralhydrology-public-a4c284b'
author_arlstm_member = f'{author_root}/neuralhydrology/modelzoo/arlstm.py'
author_sampler_member = f'{author_root}/neuralhydrology/utils/samplingutils.py'
environment_members = [
    f'{author_root}/environments/environment_cuda10_2.yml',
    f'{author_root}/environments/environment_cuda11_3.yml',
]
current_arlstm = root / 'neuralhydrology/modelzoo/arlstm.py'
current_sampler = root / 'neuralhydrology/utils/samplingutils.py'

def digest(data):
    return hashlib.sha256(data).hexdigest()

class StripAnnotations(ast.NodeTransformer):
    @staticmethod
    def _without_docstring(body):
        if (
            body
            and isinstance(body[0], ast.Expr)
            and isinstance(body[0].value, ast.Constant)
            and isinstance(body[0].value.value, str)
        ):
            return body[1:]
        return body

    def visit_arg(self, node):
        node = self.generic_visit(node)
        node.annotation = None
        node.type_comment = None
        return node

    def visit_FunctionDef(self, node):
        node = self.generic_visit(node)
        node.returns = None
        node.type_comment = None
        node.body = self._without_docstring(node.body)
        return node

    def visit_AsyncFunctionDef(self, node):
        node = self.generic_visit(node)
        node.returns = None
        node.type_comment = None
        node.body = self._without_docstring(node.body)
        return node

    def visit_ClassDef(self, node):
        node = self.generic_visit(node)
        node.body = self._without_docstring(node.body)
        return node

def selected_ast_sha(data, kind, name):
    tree = ast.parse(data.decode('utf-8'))
    selected = None
    for node in tree.body:
        if kind == 'class' and isinstance(node, ast.ClassDef) and node.name == name:
            selected = node
        if kind == 'function' and isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name:
            selected = node
    if selected is None:
        raise ValueError(f'Could not find {kind} {name}')
    selected = StripAnnotations().visit(selected)
    ast.fix_missing_locations(selected)
    return digest(ast.dump(selected, include_attributes=False).encode('utf-8'))

with zipfile.ZipFile(archive) as handle:
    author_arlstm = handle.read(author_arlstm_member)
    author_sampler = handle.read(author_sampler_member)
    author_environments = {}
    for member in environment_members:
        data = handle.read(member)
        text = data.decode('utf-8')
        relevant = [
            line.strip()
            for line in text.splitlines()
            if re.search(r'python|pytorch|cudatoolkit|numpy|pandas|xarray|scipy', line, flags=re.IGNORECASE)
        ]
        author_environments[Path(member).name] = {
            'sha256': digest(data),
            'relevant_lines': relevant,
        }

current_arlstm_bytes = current_arlstm.read_bytes()
current_sampler_bytes = current_sampler.read_bytes()
author_arlstm_ast = selected_ast_sha(author_arlstm, 'class', 'ARLSTM')
current_arlstm_ast = selected_ast_sha(current_arlstm_bytes, 'class', 'ARLSTM')
author_sampler_ast = selected_ast_sha(author_sampler, 'function', 'bernoulli_subseries_sampler')
current_sampler_ast = selected_ast_sha(current_sampler_bytes, 'function', 'bernoulli_subseries_sampler')

job_gpu_lines = {}
for job in ('202214', '202215_0', '202216_10'):
    info = subprocess.run(
        ['scontrol', 'show', 'job', '-o', job],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    fields = dict(token.split('=', 1) for token in info.split() if '=' in token)
    stdout_path = Path(fields['StdOut'])
    gpu_line = None
    if stdout_path.exists():
        for line in stdout_path.read_text(encoding='utf-8', errors='replace').splitlines()[:20]:
            if any(label in line for label in ('NVIDIA', 'Tesla', 'GeForce', 'Quadro')):
                gpu_line = line.strip()
                break
    job_gpu_lines[job] = {'stdout': str(stdout_path), 'gpu_line': gpu_line}

payload = {
    'python': sys.version.replace('\n', ' '),
    'platform': platform.platform(),
    'packages': {
        'neuralhydrology': importlib.metadata.version('neuralhydrology'),
        'numpy': numpy.__version__,
        'pandas': pandas.__version__,
        'scipy': scipy.__version__,
        'torch': torch.__version__,
        'xarray': xarray.__version__,
    },
    'torch_cuda_build': torch.version.cuda,
    'torch_cudnn_version': torch.backends.cudnn.version(),
    'torch_deterministic_algorithms_enabled': torch.are_deterministic_algorithms_enabled(),
    'torch_cudnn_benchmark': torch.backends.cudnn.benchmark,
    'torch_cudnn_deterministic': torch.backends.cudnn.deterministic,
    'author_environment_members': author_environments,
    'author_environment_interpretation': (
        'Python and CUDA toolkit are pinned, but PyTorch, NumPy, pandas, SciPy, xarray and cuDNN exact versions are not.'
    ),
    'author_arlstm_sha256': digest(author_arlstm),
    'current_arlstm_sha256': digest(current_arlstm_bytes),
    'author_arlstm_executable_ast_sha256': author_arlstm_ast,
    'current_arlstm_executable_ast_sha256': current_arlstm_ast,
    'arlstm_behavioral_ast_identical': author_arlstm_ast == current_arlstm_ast,
    'author_sampler_sha256': digest(author_sampler),
    'current_sampler_sha256': digest(current_sampler_bytes),
    'author_sampler_ast_sha256': author_sampler_ast,
    'current_sampler_ast_sha256': current_sampler_ast,
    'sampler_ast_identical': author_sampler_ast == current_sampler_ast,
    'running_job_gpu_lines': job_gpu_lines,
    'causal_boundary': (
        'Exact runtime versions and training hardware differ or are under-specified; this is a plausible source of '
        'checkpoint variation but does not by itself attribute the confirmed numerical discrepancy.'
    ),
}
print(json.dumps(payload, sort_keys=True))
PY
)

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
