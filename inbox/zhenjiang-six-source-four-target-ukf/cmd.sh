#!/usr/bin/env bash
# One bounded audit of authenticated stored tensors; no job or model execution.
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
python -B - <<'PY'
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

import mpmath as mp
import torch

ROOT = Path('/data1/home/sunyiq/zhenjiang_validation_joseph_failure_diagnostic_20261015_001')
SOURCE = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_005')
RAW_SHA = 'f7e3c39819b10a90f3b8a389487357ba2236ce2d60a6ea7eb00755fdd46ca8f5'
RESULT_SHA = '8fcd1a9a614f746255d6df59b82ae26505f1c28a1f06490c7f24f2d96d6894b4'
CODE_SHA = '91ad29057526ba7c6c503aa4c8b9e932e6d9a29044bb31e989afd22212a2c1d4'
JITTERS = [0., 1e-10, 1e-9, 1e-8, 1e-7, 1e-6, 1e-5, 1e-4]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_bytes())


def tensor_sha(tensor):
    return hashlib.sha256(tensor.contiguous().numpy().tobytes()).hexdigest()


assert not torch.cuda.is_available()
torch.set_num_threads(1)
queue = subprocess.run(['squeue', '-h', '-u', 'sunyiq', '-o', '%i|%T'],
                       check=True, capture_output=True, text=True)
assert not any(line.split('|')[0] in ('242937', '243193') for line in queue.stdout.splitlines())
accounting = subprocess.run(['sacct', '-n', '-X', '-j', '242937,243193',
                            '--format=JobID,State,ExitCode,Start,End', '-P'],
                           check=True, capture_output=True, text=True)
rows = {v[0]: v for line in accounting.stdout.splitlines()
        if (v := line.split('|'))[0] in ('242937', '243193')}
assert rows['242937'][1:3] == ['FAILED', '1:0']
assert rows['243193'][1:3] == ['COMPLETED', '0:0']
assert rows['243193'][3:5] == ['2026-10-15T23:09:55', '2026-10-15T23:23:27']
assert sha(ROOT/'diagnostic_spec.json') == '3a6952ed70f68b9ab71de76d1f0836c059aa40d2018547dfbcd7e260ec286c17'
result_path = ROOT/'evidence/diagnostic_result.json'
assert sha(result_path) == RESULT_SHA
prior = read(result_path)
assert prior['status'] == 'validation_covariance_failure_captured'
assert prior['source_complete_epochs'] == 45 and prior['source_optimizer_steps'] == 6906
assert prior['final_in_memory_optimizer_steps'] == [7060.]
assert prior['source_bytes_unchanged'] and prior['source_code_unchanged']
pinned = prior['source_file_sha256']
assert len(pinned) == 58 and all(sha(p) == h for p, h in pinned.items())
code_files = sorted([*SOURCE.joinpath('src').glob('*.py'),
                     *SOURCE.joinpath('scripts').glob('*.py'),
                     *SOURCE.joinpath('vendor/pytides').glob('*.py')])
code = {p.relative_to(SOURCE).as_posix(): sha(p) for p in code_files}
assert len(code) == 37
code_hash = hashlib.sha256(json.dumps(code, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
assert code_hash == CODE_SHA
raw_path = ROOT/'evidence/covariance_failure_operands.pt'
assert sha(raw_path) == RAW_SHA
raw = torch.load(raw_path, map_location='cpu', weights_only=True)
assert raw['original_jitters'] == JITTERS
assert raw['context'] == prior['failure_context']
assert raw['context']['epoch'] == 46 and raw['context']['validation_batch_index'] == 170
assert raw['context']['analysis_step'] == 24
assert raw['context']['window_indices'] == list(range(2704, 2720))
frames = {v['function']: v for v in raw['original_failure_traceback_frames']}
values = frames['linear_update']['tensors']
repair = frames['repair_rejected_members']
candidate = repair['tensors']['candidate']
member = repair['scalars']['i']
assert isinstance(member, int) and 0 <= member < 16
assert values['p'].shape == values['covariance'].shape == (16, 128, 128)
assert candidate.shape == (1, 128, 128)
assert all(t.dtype == torch.float64 and bool(torch.isfinite(t).all()) for t in values.values())
assert candidate.dtype == torch.float64 and bool(torch.isfinite(candidate).all())
assert torch.equal(frames['stable_cholesky']['tensors']['p'], candidate)
for key in ('p', 'complement', 'covariance', 'gain'):
    assert torch.equal(values[key], repair['tensors'][key])
assert torch.equal(values['r'], repair['tensors']['noise'])
assert bool((values['r_diagonal'] > 0).all())


def sym(t):
    return (t + t.transpose(-1, -2)) * .5


def attempts(matrix):
    result = []
    for jitter in JITTERS:
        factor, info = torch.linalg.cholesky_ex(sym(matrix) + jitter * torch.eye(matrix.shape[-1], dtype=torch.float64))
        result.append({'jitter': jitter, 'info': int(info),
                       'finite_factor': bool(torch.isfinite(factor).all())})
    return {'entry_scale': float(matrix.abs().max()),
            'stored_symmetric': torch.equal(matrix, matrix.T), 'attempts': result,
            'tensor_sha256': tensor_sha(matrix)}


cpu = []
for index in range(16):
    entry = {'member_index': index}
    for name in ('covariance', 'innovation_cov', 'p'):
        entry[name] = attempts(values[name][index])
    cpu.append(entry)
candidate_attempts = attempts(candidate[0])
moments = raw['moments']
wm, wc = moments['wm'], moments['wc']
assert wm.shape == wc.shape == (257,)
assert wm[0].item() == 0. and wc[0].item() == 2.
assert bool((wm[1:] == 1./256).all()) and bool((wc[1:] == 1./256).all())
assert all(bool(torch.isfinite(v).all()) for v in moments.values())
assert all(bool((v > 0).all()) for v in raw['noise_variances'])
q = raw['noise_variances'][0]
reconstructed_prior = sym(moments['covariance'] + torch.diag(q)[None])
ut_summary = {'mean_weight_sum': float(wm.sum()), 'covariance_weight_sum': float(wc.sum()),
              'central_mean_weight': float(wm[0]), 'central_covariance_weight': float(wc[0]),
              'all_weights_nonnegative': True, 'all_noise_variances_positive': True,
              'all_moment_tensors_finite': True,
              'prior_equals_saved_moments_plus_original_q_on_cpu': torch.equal(reconstructed_prior, values['covariance']),
              'original_process_input_dtypes': [str(v.dtype) for v in raw['actual_process_float32_inputs']],
              'original_process_output_dtype': str(raw['actual_process_output'].dtype),
              'noise_sha256': [tensor_sha(v) for v in raw['noise_variances']],
              'wm_sha256': tensor_sha(wm), 'wc_sha256': tensor_sha(wc)}


def matrix(t):
    # mp.mpf(float) preserves the binary float value at both diagnostic precisions.
    return mp.matrix([[mp.mpf(float(v)) for v in row] for row in t.tolist()])


def factor_pivots(a):
    lower = mp.matrix(a.rows)
    minimum = None
    for j in range(a.rows):
        pivot = a[j, j] - mp.fsum(lower[j, k] * lower[j, k] for k in range(j))
        minimum = pivot if minimum is None else min(minimum, pivot)
        if pivot <= 0:
            return {'positive': False, 'first_nonpositive_index': j,
                    'pivot': mp.nstr(pivot, 55), 'minimum_pivot': mp.nstr(minimum, 55)}
        lower[j, j] = mp.sqrt(pivot)
        for i in range(j + 1, a.rows):
            lower[i, j] = (a[i, j] - mp.fsum(lower[i, k] * lower[j, k] for k in range(j))) / lower[j, j]
    return {'positive': True, 'first_nonpositive_index': None, 'minimum_pivot': mp.nstr(minimum, 55)}


references, rounded = [], []
for digits in (80, 120):
    with mp.workdps(digits):
        cov = matrix(values['covariance'][member])
        stored = matrix(values['p'][member])
        compensated = matrix(candidate[0])
        a, k, noise = (matrix(values[name][member]) for name in ('complement', 'gain', 'r'))
        cov, stored, compensated = [(v + v.T) / 2 for v in (cov, stored, compensated)]
        joseph = a * cov * a.T + k * noise * k.T
        joseph = (joseph + joseph.T) / 2
        nearest = torch.tensor([[float(joseph[i, j]) for j in range(128)] for i in range(128)], dtype=torch.float64)
        ref = {'decimal_digits': digits, 'member_index': member,
               'stored_prior': factor_pivots(cov), 'stored_posterior': factor_pivots(stored),
               'stored_compensated_candidate': factor_pivots(compensated),
               'same_joseph_from_stored_operands': factor_pivots(joseph),
               'nearest_float64_reference': factor_pivots(matrix(nearest)),
               'maximum_stored_posterior_difference': mp.nstr(max(abs(stored[i, j] - joseph[i, j]) for i in range(128) for j in range(128)), 55),
               'maximum_stored_candidate_difference': mp.nstr(max(abs(compensated[i, j] - joseph[i, j]) for i in range(128) for j in range(128)), 55),
               'reference_uses_stored_gain_complement_prior_noise': True,
               'nearest_float64_reference_sha256': tensor_sha(nearest),
               'compensated_candidate_equals_nearest_float64_reference': torch.equal(candidate[0], nearest),
               'nearest_float64_cpu_attempts': attempts(nearest)}
        references.append(ref)
        rounded.append(nearest)
assert torch.equal(rounded[0], rounded[1])
for key in ('stored_prior', 'stored_posterior', 'stored_compensated_candidate',
            'same_joseph_from_stored_operands', 'nearest_float64_reference'):
    assert references[0][key]['positive'] == references[1][key]['positive']
assert all(sha(p) == h for p, h in pinned.items()) and sha(raw_path) == RAW_SHA
assert all(sha(SOURCE/name) == digest for name, digest in code.items())
at = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
record = {'status': 'joseph_failure_replay_stored_cpu_audit_preserved', 'checked_at_beijing': at.isoformat(),
          'root': str(ROOT), 'source_root': str(SOURCE), 'source_code_hash': code_hash,
          'source_identity_count': len(pinned), 'source_code_file_count': len(code),
          'source_complete_epochs': 45, 'source_optimizer_steps': 6906,
          'all_source_bytes_unchanged': True, 'all_twelve_failed_members_preserved': True,
          'operands_sha256': RAW_SHA, 'diagnostic_result_sha256': RESULT_SHA,
          'original_context': raw['context'], 'failed_member_index': member,
          'original_jitters': JITTERS, 'all_original_operands_finite': True,
          'all_observation_noise_diagonals_positive': True, 'ut_and_noise': ut_summary,
          'cpu_attempts': cpu, 'stored_candidate_cpu_attempts': candidate_attempts,
          'high_precision_diagnostic_references': references,
          'two_precision_nearest_float64_reference_equal': True,
          'diagnostic_precision_not_applied_to_training': True,
          'historical_rng_equality_established': False, 'actual_accounting': rows,
          'gpu_work_performed': False, 'training_data_values_read': False,
          'selection_data_values_read': False, 'evaluation_values_read': False,
          'formal_training_epochs_added': 0, 'optimizer_updates': 0,
          'scheduler_mutated': False, 'scientific_rules_changed': False, 'formal_recovery_admitted': False}
path = ROOT/'evidence'/('joseph_failure_stored_cpu_audit_' + at.strftime('%Y%m%d_%H%M%S_%f') + '.json')
with path.open('x', encoding='utf-8') as stream:
    json.dump(record, stream, sort_keys=True, allow_nan=False)
    stream.write('\n')
record.update(immutable_record=str(path), immutable_record_sha256=sha(path))
print(json.dumps(record, sort_keys=True, allow_nan=False))
PY
