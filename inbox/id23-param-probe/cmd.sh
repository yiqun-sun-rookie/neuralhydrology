#!/bin/bash
# Retrieve the probe artifacts: tar out/ + manifest + slurm log into this channel's outbox.
set -o pipefail
ROOT=/data1/home/sunyiq/id23_param_probe
OUT=~/hpc_mailbox/outbox/id23-param-probe
mkdir -p "$OUT/payload"
cd "$ROOT" || exit 1
cp logs/par_probe_219209.out out/slurm_219209.out 2>/dev/null
cp run_manifest.tsv out/ 2>/dev/null
cp par_probe.slurm out/ 2>/dev/null
tar czf "$OUT/payload/parameter_axis_probe_v01_out_20260903.tar.gz" -C "$ROOT" out
sha256sum "$OUT/payload/parameter_axis_probe_v01_out_20260903.tar.gz" | tee "$OUT/payload/parameter_axis_probe_v01_out_20260903.tar.gz.sha256"
echo "=== per-file sha256 ==="
(cd "$ROOT/out" && sha256sum *.csv *.json)
ls -la "$OUT/payload/"
