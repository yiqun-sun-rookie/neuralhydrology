#!/bin/bash
# read-only health probe for jobs 246240,246243,246450,246280,246281,246378
cd /data1/home/sunyiq/ohn_da_vs_ar_531_20261021 || exit 1
echo "=== NOW ==="; date +%s
echo "=== SACCT ==="
sacct -X -n -P -j 246240,246243,246450,246280,246281,246378 --format=JobID,JobName,State,ExitCode,Elapsed,NodeList 2>&1
echo "=== SQUEUE ==="
squeue -j 246240,246243,246450,246280,246281,246378 -h -o '%i|%T|%R|%M|%l' 2>&1
echo "=== LOGAGE ==="
ls -1 logs | grep -E '(246240_|246243_|246450_|246280_|246281_|246378_)' | while read f; do echo "$f $(stat -c %Y logs/$f) $(stat -c %s logs/$f)"; done
echo "=== SPEED ==="
for f in $(ls -1 logs | grep -E '(246240_|246243_|246450_|246280_|246281_|246378_).*\.out$'); do s=$(tr '\r' '\n' < logs/$f | grep -oE '[0-9]+/531 \[[^]]*, *[0-9.]+s/it\]' | tail -1); [ -n "$s" ] && echo "$f $s"; done
echo "=== CKPT ==="
for d in runs/a1_s10*; do [ -d "$d" ] || continue; n=$(ls $d/model_epoch*.pt 2>/dev/null | wc -l); nw=$(ls -t $d/model_epoch*.pt 2>/dev/null | head -1); echo "$(basename $d) $n ${nw:+$(stat -c %Y $nw)}"; done
echo "=== MARKERS ==="
ls logs | grep -E '^done_a1_s10' ; for f in copies/p2/*/*/da_eval_stamp_test_every3_da.json; do [ -f "$f" ] && { d=$(dirname $f); z=$d/test/model_epoch050/test_results_data_assimilation.zarr; [ -d "$z" ] && echo "STAMP $f zarr_ok" || echo "STAMP $f ZARR_MISSING"; }; done
echo "=== ERRTAILS ==="
for f in $(ls -1 logs | grep -E '(246240_|246243_|246450_|246280_|246281_|246378_).*\.(err|out)$'); do if grep -qE 'Traceback|CUDA error|RuntimeError|FATAL|MISSING|STALE_RUN|AMBIGUOUS|CONDA_FAILED|Killed|oom' logs/$f; then echo "--- $f"; grep -hE 'Error|FATAL|MISSING|STALE|AMBIGUOUS|Killed|oom' logs/$f | tail -3; fi; done
echo "=== P3 ==="
cat results/p3/p3_verdicts.json 2>/dev/null
echo END_STATUS
