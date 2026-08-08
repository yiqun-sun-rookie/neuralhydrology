#!/bin/bash
# ID29 seq=16: hourly progress check. Short, read-only, no waiting.
ROOT=/data1/home/sunyiq/nearing2022_da
RES=$ROOT/results/29_nearing2022_da_ar

echo "=== queue ==="
squeue -j 201890,201893 -o "%.10i %.10j %.10T %.12M %.12L" 2>&1

echo "=== assimilation (201890) ==="
tr '\r' '\n' < "$ROOT/logs/da_201890.out" 2>/dev/null | grep -oE "Evaluation: *[0-9]+%\|[^|]*\| *[0-9]+/[0-9]+ \[[^]]*\]" | tail -1 | sed 's/^/  /'

echo "=== autoregression (201893) ==="
A=$(ls -1dt $RES/nearing2022_autoregression_*/ 2>/dev/null | head -1)
echo "  epochs: $(grep -cE 'Epoch [0-9]+ average loss' "$A/output.log" 2>/dev/null) / 30"
grep -E "Epoch [0-9]+ average loss" "$A/output.log" 2>/dev/null | tail -1 | sed 's/^/  /'

echo "=== errors ==="
grep -icE "traceback|out of memory" "$ROOT"/logs/da_201890.err "$ROOT"/logs/ar_201893.err 2>/dev/null
