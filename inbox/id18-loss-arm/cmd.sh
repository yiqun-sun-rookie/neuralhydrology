#!/bin/bash
# ID18 seq=12: final corrected read-only isolation audit after smoke job 202067.
set -eo pipefail

TARGET=/data1/home/sunyiq/id18_e04_20260809
RESULT=$TARGET/results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482

python - <<'PY'
import hashlib
import json
import pathlib

root = pathlib.Path('/data1/home/sunyiq/id18_e04_20260809')
result = root / 'results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482'
preflight = json.loads((result / 'protocol/preflight.json').read_text(encoding='utf-8'))

source_mismatches = []
for item in preflight['source_files']:
    actual = hashlib.sha256((root / item['path']).read_bytes()).hexdigest()
    if actual != item['sha256']:
        source_mismatches.append(item['path'])
config_mismatches = []
for item in preflight['generated_configs']:
    actual = hashlib.sha256((result / item['path']).read_bytes()).hexdigest()
    if actual != item['sha256']:
        config_mismatches.append(item['path'])

conceptual_files = sorted((result / 'smoke/conceptual').glob('*/*/completion.json'))
neural_files = sorted((result / 'smoke/neural_completions').glob('*.json'))
assert len(conceptual_files) == 6, conceptual_files
assert len(neural_files) == 2, neural_files
for path in conceptual_files:
    payload = json.loads(path.read_text(encoding='utf-8'))
    assert payload['settings']['non_scientific_smoke'] is True, path
    assert int(payload['basin_count']) == 1, path
for path in neural_files:
    payload = json.loads(path.read_text(encoding='utf-8'))
    assert payload['non_scientific_smoke'] is True, path
    assert int(payload['integrity']['basin_count']) == 1, path

formal_conceptual = sorted((result / 'conceptual').glob('*/*/completion.json'))
formal_neural = sorted((result / 'protocol/neural_completions').glob('*.json'))
assert not source_mismatches, source_mismatches
assert not config_mismatches, config_mismatches
assert not formal_conceptual, formal_conceptual
assert not formal_neural, formal_neural

print(json.dumps({
    'source_hash_mismatches': source_mismatches,
    'config_hash_mismatches': config_mismatches,
    'smoke_conceptual_completions': [str(p.relative_to(result)) for p in conceptual_files],
    'smoke_neural_completions': [str(p.relative_to(result)) for p in neural_files],
    'formal_conceptual_completions': [],
    'formal_neural_completions': [],
}, indent=2))
PY

echo "E04_POST_SMOKE_ISOLATION_PASS"
