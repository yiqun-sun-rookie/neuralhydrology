#!/usr/bin/env bash
# Read three fixed checkpoint archives as inert file metadata; no numerical imports.
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -I - <<'PY'
import base64
import collections
import datetime
import hashlib
import io
import json
import math
import pathlib
import pickle
import pickletools
import resource
import struct
import sys
import zipfile

resource.setrlimit(resource.RLIMIT_CPU, (30, 30))
resource.setrlimit(resource.RLIMIT_AS, (268435456, 268435456))
ROOT = pathlib.Path('/data1/home/sunyiq/zhenjiang_5s5t_stage_b_20260907_001')
FAMILY = 'ZHENJIANG_FIVE_SOURCE_FIVE_TARGET_D32_GRU_SINGLE_ANALYSIS_UKF_ORACLE_DATONG_V2'
STATIONS = ['nanjing', 'zhenjiang', 'jiangyin', 'xuliujing', 'wusongkou']
EXPECTED = {
    17: (1326548, '25878bef7e6456c29e1fee143009e2afc2670b8177f5b2d3367faeaa7c2b1701', 3, 0.08884079544782522, '374d3278c7e41dee0e2c1e937f936df442a44348a02addd46a2c4bb5b13b8263'),
    29: (1137556, '9124c4d398dd9ceb4afd30bd6a090dce6803592728e1bca474e348ce47a05222', 2, 0.1071206355715569, '7e8a0376f47b3c7f217e004df2519b48dce3311ceb5f3203e1f844eb97c4ff46'),
    43: (1137556, 'b24d691d375b7f4a53478d7023a9bb4ca5b55ca3ffc2ec02c46cb8b408ae7a84', 2, 0.08999388922047184, '79b04446f4407496ceb8f0d85442ac2fe8ecd60db2d64e18c90a0bf3a13fe961'),
}
READS = []
GLOBALS = set()

def emit(section, value):
    print(json.dumps({'section': section, 'value': value}, sort_keys=True, allow_nan=False), flush=True)

def now():
    return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()

class DoubleStorageTag:
    def __new__(cls, *args):
        raise RuntimeError('storage constructor execution forbidden')

def inert_tensor(storage, offset, size, stride, requires_grad, hooks, metadata=None):
    if type(storage) is not tuple or len(storage) != 4 or storage[0] != 'storage':
        raise RuntimeError('unsupported storage descriptor')
    if requires_grad is not False or hooks:
        raise RuntimeError('unexpected tensor gradient or hooks')
    if metadata not in (None, {}):
        raise RuntimeError('unsupported tensor metadata')
    return ('inert_tensor', storage, offset, size, stride)

class MetadataReader(pickle.Unpickler):
    def find_class(self, module, name):
        GLOBALS.add(module + '.' + name)
        if (module, name) == ('torch', 'DoubleStorage'):
            return DoubleStorageTag
        if (module, name) == ('torch._utils', '_rebuild_tensor_v2'):
            return inert_tensor
        if (module, name) == ('collections', 'OrderedDict'):
            return collections.OrderedDict
        raise RuntimeError('pickle global forbidden: ' + module + '.' + name)

    def persistent_load(self, value):
        if (type(value) is not tuple or len(value) != 5 or value[0] != 'storage'
                or value[1] is not DoubleStorageTag or value[3] != 'cpu'):
            raise RuntimeError('unsupported persistent storage')
        key, count = value[2], value[4]
        if type(key) is not str or not key.isdecimal() or type(count) is not int or count not in (5, 27):
            raise RuntimeError('unexpected storage key or count')
        return ('storage', key, 'cpu', count)

def stat_identity(value):
    return (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_ctime_ns)

def read_one(seed):
    size, digest, best_epoch, metric, source_digest = EXPECTED[seed]
    path = ROOT / 'runs' / 'stage_b' / ('seed_' + str(seed)) / 'best_checkpoint.pt'
    if path.resolve(strict=True) != path:
        raise RuntimeError('redirected checkpoint path')
    before = path.stat()
    if before.st_size != size:
        raise RuntimeError('checkpoint size drift')
    with path.open('rb') as handle:
        raw = handle.read(size + 1)
    READS.append(str(path))
    if len(raw) != size or hashlib.sha256(raw).hexdigest() != digest:
        raise RuntimeError('checkpoint raw identity drift')
    with zipfile.ZipFile(io.BytesIO(raw), 'r') as archive:
        infos = archive.infolist()
        names = [entry.filename for entry in infos]
        if len(names) != len(set(names)) or len(names) > 16:
            raise RuntimeError('unexpected archive members')
        for entry in infos:
            if (entry.file_size > 2097152 or entry.flag_bits & 1
                    or '..' in pathlib.PurePosixPath(entry.filename).parts
                    or pathlib.PurePosixPath(entry.filename).is_absolute()):
                raise RuntimeError('unsafe archive member')
        metadata_names = [name for name in names if name.endswith('/data.pkl')]
        if len(metadata_names) != 1:
            raise RuntimeError('missing unique tensor metadata')
        prefix = metadata_names[0][:-len('data.pkl')]
        if archive.read(prefix + 'byteorder') != b'little':
            raise RuntimeError('unsupported storage byte order')
        metadata = archive.read(metadata_names[0])
        for opcode, argument, position in pickletools.genops(metadata):
            if opcode.name in {'EXT1', 'EXT2', 'EXT4', 'INST', 'OBJ', 'NEWOBJ', 'NEWOBJ_EX', 'BUILD'}:
                raise RuntimeError('pickle opcode forbidden: ' + opcode.name)
        payload = MetadataReader(io.BytesIO(metadata)).load()
        if type(payload) is not dict:
            raise RuntimeError('unexpected checkpoint payload')
        for key, value in {
            'schema_version': '2.0', 'experiment_family': FAMILY,
            'stage': 'stage_b', 'boundary_mode': 'retrospective_observed_oracle',
            'model_seed': seed, 'best_epoch': best_epoch, 'best_selection_metric_m': metric,
            'trainable_scalar_count': 10, 'stage_a_checkpoint_sha256': source_digest,
            'distinguishability_passes': [True] * 5,
        }.items():
            if payload.get(key) != value:
                raise RuntimeError('checkpoint identity mismatch: ' + key)
        if payload['upstream_sha256']['data_contract_sha256'] != '688ee2340954542b71955df35dd1f918450e0b01035f16b5bf353ce8ffbb798f':
            raise RuntimeError('execution contract identity mismatch')
        vectors = {}
        for key, count in [('raw_process_standard_deviation', 5),
                           ('raw_observation_standard_deviation', 5),
                           ('fixed_hidden_process_variance', 27)]:
            descriptor = payload[key]
            if type(descriptor) is not tuple or len(descriptor) != 5 or descriptor[0] != 'inert_tensor':
                raise RuntimeError('unexpected tensor descriptor: ' + key)
            _, storage, offset, shape, stride = descriptor
            if storage[3] != count or offset != 0 or shape != (count,) or stride != (1,):
                raise RuntimeError('unexpected tensor layout: ' + key)
            member = prefix + 'data/' + storage[1]
            storage_bytes = archive.read(member)
            if len(storage_bytes) != 8 * count:
                raise RuntimeError('unexpected float64 storage length')
            values = list(struct.unpack('<' + str(count) + 'd', storage_bytes))
            if not all(math.isfinite(value) for value in values):
                raise RuntimeError('nonfinite parameter value')
            if count == 27 and values != [0.001] * 27:
                raise RuntimeError('fixed hidden variance changed')
            vectors[key] = {'values': values, 'dtype': 'float64', 'shape': [count],
                            'archive_member': member, 'byte_order': 'little',
                            'raw_storage_base64': base64.b64encode(storage_bytes).decode('ascii'),
                            'raw_storage_sha256': hashlib.sha256(storage_bytes).hexdigest()}
    if stat_identity(before) != stat_identity(path.stat()):
        raise RuntimeError('checkpoint changed during read')
    return {'seed': seed, 'checkpoint_path': str(path), 'checkpoint_bytes': size,
            'checkpoint_sha256': digest, 'best_epoch': best_epoch,
            'best_selection_metric_m': metric, 'stage_a_checkpoint_sha256': source_digest,
            'checkpoint_metadata_unchanged': True, 'station_order': STATIONS, 'vectors': vectors,
            'upstream_sha256': payload['upstream_sha256'],
            'training_config': payload['training_config'],
            'selection_log': payload['selection_log']}

emit('query_start', {'at_beijing': now(), 'job': '223517', 'python': sys.executable,
                    'mode': 'stdlib_inert_checkpoint_metadata_reader',
                    'numerical_libraries_imported': False})
try:
    if ROOT.resolve(strict=True) != ROOT:
        raise RuntimeError('redirected calibration root')
    for seed in (17, 29, 43):
        emit('checkpoint_parameter_evidence', read_one(seed))
    forbidden = [name for name in ('torch', 'numpy', 'pandas', 'scipy') if name in sys.modules]
    if forbidden:
        raise RuntimeError('unexpected numerical import')
    emit('query_end', {'at_beijing': now(), 'status': 'complete', 'checkpoint_reads': READS,
                       'checkpoint_count': len(READS), 'allowed_inert_pickle_globals': sorted(GLOBALS),
                       'formal_data_reads': 0, 'numerical_libraries_imported': False,
                       'training_or_evaluation_performed': False, 'remote_files_written': 0,
                       'effective_variance_conversion': 'deferred_to_local_machine'})
except BaseException as error:
    emit('query_end', {'at_beijing': now(), 'status': 'failed', 'checkpoint_reads': READS,
                       'error_type': type(error).__name__, 'error': str(error)})
    raise
PY
