#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== ERR OF TASK 27 ==="
tail -40 $ROOT/logs/tukf23_train_213028_27.err 2>/dev/null || echo "no err file"
echo "=== OUT OF TASK 27 ==="
tail -10 $ROOT/logs/tukf23_train_213028_27.out 2>/dev/null || echo "no out file"
echo "=== ERR FILE LIST SAMPLE ==="
ls $ROOT/logs/ | grep "213028_27" || ls $ROOT/logs/ | tail -6
