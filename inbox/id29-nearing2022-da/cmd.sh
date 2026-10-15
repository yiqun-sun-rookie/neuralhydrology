set -o pipefail
# READ-ONLY: replacement-chain state check for ID29 warmup pair (seq 734)
ROOT=/data1/home/sunyiq/nearing2022_da
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
date --iso-8601=seconds
echo "=== sacct replacement + failed jobs ==="
sacct -X -n -P -j 202506,202507,202510,202511,219423 --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null || echo "sacct failed"
echo "=== squeue N22 ==="
squeue -u sunyiq -h -o '%.12i %.18j %.9T %R' 2>/dev/null | grep -E 'N22' || echo 'none'
echo "=== v2 output dirs ==="
for S in author_v13_training_data_port_all531_v2 author_v13_warmup_isolation_all531_v2; do
  if [ -d "$D/$S" ]; then echo "PRESENT $S"; ls -1 "$D/$S" 2>/dev/null | head -20; else echo "MISSING $S"; fi
done
echo "=== receipts (key fields) ==="
for S in author_v13_training_data_port_all531_v2 author_v13_warmup_isolation_all531_v2; do
  R="$D/$S/diagnostic_receipt.json"
  if [ -f "$R" ]; then echo "--- $S"; sha256sum "$R"; grep -oE '"(schema|slurm_job_id|single_mask_restores_released_training_data_for_531_basins|registered_matrix_modified)": *[^,}]*' "$R" || true; else echo "--- $S receipt MISSING"; fi
done
echo "=== submission receipt / verifier outputs ==="
for F in warmup_target_repair_submission_01.json; do [ -f "$D/$F" ] && sha256sum "$D/$F" || echo "MISSING $F"; done
find "$D" -maxdepth 1 -iname '*verif*' 2>/dev/null | head
echo "=== server preparer/runner hashes ==="
sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm" "$ROOT/src/29_nearing2022_da_ar/scripts/verify_warmup_target_replacement_chain.py" 2>&1
echo "=== server repo head ==="
cd "$ROOT" && git log -1 --format='%h %ci %s' 2>&1 | head -1; git status --porcelain 2>/dev/null | wc -l
exit 0
