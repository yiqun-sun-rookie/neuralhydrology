#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
test ! -L '/data1/home/sunyiq/us_saved_observation_zero_diagnostic_20261008_001'
test "$(readlink -e '/data1/home/sunyiq/us_saved_observation_zero_diagnostic_20261008_001')" = '/data1/home/sunyiq/us_saved_observation_zero_diagnostic_20261008_001'
printf '%s  %s\n' '4326d11a5b980e0c057ca54a9eee5e210e8506f4a505889365b282eb918cf585' '/data1/home/sunyiq/us_saved_observation_zero_diagnostic_20261008_001/src/collect_saved_observation_v1.py' | sha256sum -c -
timeout --signal=KILL 25 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -X utf8 '/data1/home/sunyiq/us_saved_observation_zero_diagnostic_20261008_001/src/collect_saved_observation_v1.py'
