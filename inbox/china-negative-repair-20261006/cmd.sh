#!/bin/bash
set -eo pipefail
test "$(id -un)" = sunyiq
test ! -L '/data1/home/sunyiq/us_flow_representation_pair_diagnostic_20261008_001'
test "$(readlink -e '/data1/home/sunyiq/us_flow_representation_pair_diagnostic_20261008_001')" = '/data1/home/sunyiq/us_flow_representation_pair_diagnostic_20261008_001'
printf '%s  %s\n' '2450045aef6833723b10ee2a8dee2826a10ba93f8f0c225002ce3cd4edfdadaa' '/data1/home/sunyiq/us_flow_representation_pair_diagnostic_20261008_001/src/collect_flow_pair_v1.py' | sha256sum -c -
printf '%s  %s\n' 'aea21083e42681169689a2508817abf936fed9463f990359b059335e464e8863' '/data1/home/sunyiq/us_flow_representation_pair_diagnostic_20261008_001/src/diagnostic_status_v1.py' | sha256sum -c -
timeout --signal=KILL 25 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -X utf8 '/data1/home/sunyiq/us_flow_representation_pair_diagnostic_20261008_001/src/collect_flow_pair_v1.py'
