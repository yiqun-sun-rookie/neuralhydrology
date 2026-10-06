#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
root=/data1/home/sunyiq/china_negative_repair_20261006_001
test "$(timeout 10 readlink -e "$root")" = "$root"
printf 'READ_ONLY_ENVIRONMENT_PATH_DIAGNOSIS_UTC='
date -u '+%Y-%m-%dT%H:%M:%SZ'
candidate=/data1/home/sunyiq/china_negative_repair_20261006_002
if test -e "$candidate" || test -L "$candidate"; then printf 'NEXT_ROOT_OCCUPIED=%s\n' "$candidate"; else printf 'NEXT_ROOT_ABSENT=%s\n' "$candidate"; fi
timeout 20 bash <<'ENVIRONMENT_PATH_PROBE'
set +e
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
profile_exit=$?
printf 'PROFILE_SOURCE_EXIT=%s\n' "$profile_exit"
if test "$profile_exit" -ne 0; then exit "$profile_exit"; fi
conda activate nh_final
activation_exit=$?
printf 'CONDA_ACTIVATION_EXIT=%s\n' "$activation_exit"
if test "$activation_exit" -ne 0; then exit "$activation_exit"; fi
actual=$(command -v python)
expected=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
printf 'ACTUAL_PYTHON_COMMAND=%s\n' "$actual"
actual_canonical=$(readlink -f "$actual")
expected_canonical=$(readlink -f "$expected")
printf 'ACTUAL_PYTHON_CANONICAL=%s\n' "$actual_canonical"
printf 'EXPECTED_PYTHON_LITERAL=%s\n' "$expected"
printf 'EXPECTED_PYTHON_CANONICAL=%s\n' "$expected_canonical"
ls -l -- "$expected" /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python3 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python3.11
test "$actual_canonical" = "$expected"
printf 'OLD_LITERAL_PATH_TEST_EXIT=%s\n' "$?"
test "$actual_canonical" = "$expected_canonical"
printf 'BOTH_CANONICAL_PATH_TEST_EXIT=%s\n' "$?"
ENVIRONMENT_PATH_PROBE
printf 'READ_ONLY_ENVIRONMENT_PATH_DIAGNOSIS_COMPLETE\n'
