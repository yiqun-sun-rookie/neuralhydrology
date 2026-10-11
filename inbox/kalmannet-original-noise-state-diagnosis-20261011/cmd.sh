#!/bin/bash
set -eo pipefail
printf 'PREFLIGHT_START\n'
date -Is
test ! -e /data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011
test -r /data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261009_recovery5/code/evaluate.py
test -x /data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python
scontrol show partition
squeue --user=sunyiq --noheader --format='%i|%j|%P|%t|%C|%R'
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'PREFLIGHT_PYTHON'
import sys, platform, numpy, scipy, psutil, hashlib, json
from pathlib import Path
old = Path('/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261009_recovery5')
print('RUNTIME_JSON=' + json.dumps({'executable':sys.executable,'python':platform.python_version(), 'numpy':numpy.__version__, 'scipy':scipy.__version__, 'psutil':psutil.__version__, 'numpy_binary_sha256':hashlib.sha256(Path(numpy.core._multiarray_umath.__file__).read_bytes()).hexdigest(), 'original_entry_sha256':hashlib.sha256((old/'code/evaluate.py').read_bytes()).hexdigest()}))
PREFLIGHT_PYTHON
printf 'PREFLIGHT_COMPLETE_NO_SCIENTIFIC_RUN\n'
