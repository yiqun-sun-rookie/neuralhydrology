#!/usr/bin/env bash
# One authorized read-only checkpoint-parameter query for completed job 223517.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -B -I - <<'PY'
import datetime
import hashlib
import io
import json
import pathlib
import stat
import sys

import torch
from torch.nn import functional as F


ROOT = pathlib.Path('/data1/home/sunyiq/zhenjiang_5s5t_stage_b_20260907_001')
JOB = '223517'
STATIONS = ('nanjing', 'zhenjiang', 'jiangyin', 'xuliujing', 'wusongkou')
MINIMUM_NOISE_STANDARD_DEVIATION = 1e-4
EXPECTED = {
    17: {
        'size_bytes': 1326548,
        'sha256': '25878bef7e6456c29e1fee143009e2afc2670b8177f5b2d3367faeaa7c2b1701',
        'best_epoch': 3,
        'best_selection_metric_m': 0.08884079544782522,
    },
    29: {
        'size_bytes': 1137556,
        'sha256': '9124c4d398dd9ceb4afd30bd6a090dce6803592728e1bca474e348ce47a05222',
        'best_epoch': 2,
        'best_selection_metric_m': 0.1071206355715569,
    },
    43: {
        'size_bytes': 1137556,
        'sha256': 'b24d691d375b7f4a53478d7023a9bb4ca5b55ca3ffc2ec02c46cb8b408ae7a84',
        'best_epoch': 2,
        'best_selection_metric_m': 0.08999388922047184,
    },
}
EXPECTED_KEYS = {
    'schema_version',
    'experiment_family',
    'boundary_mode',
    'stage',
    'model_seed',
    'best_epoch',
    'best_selection_metric_m',
    'trainable_scalar_count',
    'stage_a_checkpoint_sha256',
    'upstream_sha256',
    'distinguishability_passes',
    'training_config',
    'training_log',
    'selection_log',
    'raw_process_standard_deviation',
    'raw_observation_standard_deviation',
    'fixed_hidden_process_variance',
}


def now_beijing():
    zone = datetime.timezone(datetime.timedelta(hours=8))
    return datetime.datetime.now(zone).isoformat()


def emit(section, value):
    print(json.dumps(
        {'section': section, 'value': value},
        ensure_ascii=False,
        sort_keys=True,
        allow_nan=False,
    ), flush=True)


def immutable_stat(value):
    return {
        'device': int(value.st_dev),
        'inode': int(value.st_ino),
        'mode': int(stat.S_IMODE(value.st_mode)),
        'uid': int(value.st_uid),
        'gid': int(value.st_gid),
        'size_bytes': int(value.st_size),
        'modified_time_ns': int(value.st_mtime_ns),
    }


def require_tensor(payload, name):
    value = payload[name]
    if not isinstance(value, torch.Tensor):
        raise RuntimeError(name + ' is not a tensor')
    if value.device.type != 'cpu' or value.dtype != torch.float64:
        raise RuntimeError(name + ' must be a CPU float64 tensor')
    if tuple(value.shape) != (5,):
        raise RuntimeError(name + ' must contain exactly five values')
    if not bool(torch.isfinite(value).all()):
        raise RuntimeError(name + ' contains a nonfinite value')
    return value.detach().clone()


def checkpoint_path(seed):
    candidate = ROOT / 'runs' / 'stage_b' / ('seed_' + str(seed)) / 'best_checkpoint.pt'
    if candidate.resolve() != candidate or ROOT not in candidate.parents:
        raise RuntimeError('checkpoint path is redirected or escaped')
    if not candidate.is_file() or candidate.is_symlink():
        raise RuntimeError('checkpoint file is missing or redirected: ' + str(candidate))
    return candidate


def load_one(seed):
    expected = EXPECTED[seed]
    path = checkpoint_path(seed)
    before = immutable_stat(path.stat())
    with path.open('rb') as handle:
        raw = handle.read()
    digest = hashlib.sha256(raw).hexdigest()
    if len(raw) != expected['size_bytes'] or digest != expected['sha256']:
        raise RuntimeError('checkpoint raw identity mismatch for seed ' + str(seed))
    payload = torch.load(io.BytesIO(raw), map_location='cpu', weights_only=True)
    raw = None
    after = immutable_stat(path.stat())
    if before != after:
        raise RuntimeError('checkpoint metadata changed while reading seed ' + str(seed))
    if type(payload) is not dict or set(payload) != EXPECTED_KEYS:
        raise RuntimeError('checkpoint payload keys mismatch for seed ' + str(seed))
    expected_identity = {
        'schema_version': '2.0',
        'experiment_family': 'ZHENJIANG_FIVE_SOURCE_FIVE_TARGET_D32_GRU_SINGLE_ANALYSIS_UKF_ORACLE_DATONG_V2',
        'boundary_mode': 'retrospective_observed_oracle',
        'stage': 'stage_b',
        'model_seed': seed,
        'best_epoch': expected['best_epoch'],
        'trainable_scalar_count': 10,
    }
    for name, value in expected_identity.items():
        if payload[name] != value:
            raise RuntimeError('checkpoint identity mismatch for ' + name)
    if float(payload['best_selection_metric_m']) != expected['best_selection_metric_m']:
        raise RuntimeError('best selection metric mismatch for seed ' + str(seed))
    if payload['distinguishability_passes'] != [True, True, True, True, True]:
        raise RuntimeError('distinguishability evidence mismatch for seed ' + str(seed))
    process_raw = require_tensor(payload, 'raw_process_standard_deviation')
    observation_raw = require_tensor(payload, 'raw_observation_standard_deviation')
    hidden = payload['fixed_hidden_process_variance']
    if not isinstance(hidden, torch.Tensor) or hidden.device.type != 'cpu':
        raise RuntimeError('fixed hidden process variance is not a CPU tensor')
    if hidden.dtype != torch.float64 or tuple(hidden.shape) != (27,):
        raise RuntimeError('fixed hidden process variance contract mismatch')
    if not torch.equal(hidden, torch.full((27,), 0.001, dtype=torch.float64)):
        raise RuntimeError('fixed hidden process variance values mismatch')
    process_standard_deviation = MINIMUM_NOISE_STANDARD_DEVIATION + F.softplus(process_raw)
    observation_standard_deviation = MINIMUM_NOISE_STANDARD_DEVIATION + F.softplus(observation_raw)
    process_variance = process_standard_deviation.square()
    observation_variance = observation_standard_deviation.square()
    for name, value in (
        ('effective process variance', process_variance),
        ('effective observation variance', observation_variance),
    ):
        if not bool(torch.isfinite(value).all()) or not bool((value > 0.0).all()):
            raise RuntimeError(name + ' is not finite and positive')
    return {
        'seed': seed,
        'checkpoint': {
            'path': str(path),
            'size_bytes': before['size_bytes'],
            'sha256': digest,
            'raw_file_read_count_in_this_query': 1,
            'metadata_unchanged_during_read': True,
        },
        'payload_identity': {
            **expected_identity,
            'best_selection_metric_m': float(payload['best_selection_metric_m']),
            'stage_a_checkpoint_sha256': payload['stage_a_checkpoint_sha256'],
            'distinguishability_passes': payload['distinguishability_passes'],
        },
        'station_order': list(STATIONS),
        'raw_process_standard_deviation': process_raw.tolist(),
        'effective_process_standard_deviation_normalized': process_standard_deviation.tolist(),
        'effective_process_variance_normalized_squared': process_variance.tolist(),
        'raw_observation_standard_deviation': observation_raw.tolist(),
        'effective_observation_standard_deviation_normalized': observation_standard_deviation.tolist(),
        'effective_observation_variance_normalized_squared': observation_variance.tolist(),
        'fixed_hidden_process_variance_count': 27,
        'fixed_hidden_process_variance_normalized_squared': 0.001,
    }


emit('query_start', {
    'at_beijing': now_beijing(),
    'job': JOB,
    'root': str(ROOT),
    'python': sys.executable,
    'torch_version': torch.__version__,
    'authorized_checkpoint_paths_only': True,
    'formal_data_contents_opened': False,
    'evaluation_performed': False,
})
try:
    if not ROOT.is_dir() or ROOT.resolve() != ROOT:
        raise RuntimeError('fixed calibration root is absent or redirected')
    if not str(torch.__version__).startswith('2.4.0'):
        raise RuntimeError('unexpected PyTorch version for weights-only loading')
    evidence = []
    for model_seed in (17, 29, 43):
        row = load_one(model_seed)
        evidence.append(row)
        emit('checkpoint_parameter_evidence', row)
    emit('query_end', {
        'at_beijing': now_beijing(),
        'status': 'complete',
        'checkpoint_contents_opened': True,
        'checkpoint_deserialization_mode': 'torch.load(weights_only=True,map_location=cpu)',
        'checkpoint_count': len(evidence),
        'checkpoint_total_bytes': sum(row['checkpoint']['size_bytes'] for row in evidence),
        'effective_variance_formula': '(0.0001 + torch.nn.functional.softplus(raw_standard_deviation)) ** 2',
        'effective_variance_units': 'normalized_stage_units_squared',
        'formal_data_contents_opened': False,
        'training_performed': False,
        'evaluation_performed': False,
        'job_submitted_retried_requeued_or_cancelled': False,
        'year_2023_or_2024_contents_opened': False,
    })
except BaseException as error:
    emit('query_end', {
        'at_beijing': now_beijing(),
        'status': 'failed_no_retry',
        'error_type': type(error).__name__,
        'error': str(error),
        'formal_data_contents_opened': False,
        'training_performed': False,
        'evaluation_performed': False,
        'job_submitted_retried_requeued_or_cancelled': False,
        'year_2023_or_2024_contents_opened': False,
    })
    raise
PY
