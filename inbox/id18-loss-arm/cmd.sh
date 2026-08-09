#!/bin/bash
# ID18 seq=4: read-only search for an existing cma installation or cached wheel. No sbatch.
set -eo pipefail

echo "=== TIME_AND_RUNNER ==="
date -Is
echo "runner delivered id18-loss-arm seq=4"

echo "=== CONDA_ENVIRONMENTS ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda env list 2>&1

echo "=== CMA_IN_EXISTING_ENVIRONMENTS ==="
find /data1/home/sunyiq/miniconda3/envs -maxdepth 5 -type d -name cma -print 2>/dev/null | head -30

echo "=== CMA_IN_BASE_INSTALL ==="
find /data1/home/sunyiq/miniconda3/lib -maxdepth 4 -type d -name cma -print 2>/dev/null | head -30

echo "=== CMA_IN_PROJECTS ==="
find /data1/home/sunyiq/neuralhydrology -maxdepth 5 -type d -name cma -print 2>/dev/null | head -30

echo "=== CACHED_CMA_ARTIFACTS ==="
find /data1/home/sunyiq/.cache/pip -maxdepth 7 -type f \( -iname 'cma-*.whl' -o -iname 'cma-*.tar.gz' \) -print 2>/dev/null | head -30

echo "E04_CMA_SEARCH_COMPLETE"
