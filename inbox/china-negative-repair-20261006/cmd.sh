#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
test ! -L '/data1/home/sunyiq/us_saved_observation_full_diagnostic_20261008_001'
test "$(readlink -e '/data1/home/sunyiq/us_saved_observation_full_diagnostic_20261008_001')" = '/data1/home/sunyiq/us_saved_observation_full_diagnostic_20261008_001'
printf '%s  %s\n' 'a661c6e443358400822b7d8bcc2d56968b25b467bb5f12e17f5104b040bcda23' '/data1/home/sunyiq/us_saved_observation_full_diagnostic_20261008_001/src/collect_saved_observation_v1.py' | sha256sum -c -
timeout --signal=KILL 25 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -X utf8 '/data1/home/sunyiq/us_saved_observation_full_diagnostic_20261008_001/src/collect_saved_observation_v1.py'
