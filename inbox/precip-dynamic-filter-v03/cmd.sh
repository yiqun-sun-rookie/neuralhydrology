#!/usr/bin/env bash
set -eo pipefail
task_root="/data1/home/sunyiq/precip_dynamic_filter_20260930/run_20261001_211612_19f6cfd5"
test "$(readlink -f "$task_root")" = "$task_root"
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
for task_file in synthetic/tests_stdout.txt synthetic/tests.xml; do
    printf '\nFILE=%s\n' "$task_file"
    test -f "$task_root/$task_file"
    cat "$task_root/$task_file"
done
