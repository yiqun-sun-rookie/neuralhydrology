#!/bin/bash
# kalmannet-daily-perbasin sequence=181: READ-ONLY observation (analysis). No sbatch, no scancel, no writes.
set -o pipefail
echo "channel=kalmannet-daily-perbasin sequence=181 purpose=observe-analysis"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
emit_json() { f="$1"; if [ -f "$f" ]; then echo "JSON_BEGIN path=$f bytes=$(stat -c %s "$f") sha256=$(sha256sum "$f" | cut -c1-64)"; cat "$f"; echo; echo "JSON_END path=$f"; else echo "FILE_ABSENT path=$f"; fi; }
tail_file() { f="$1"; n="$2"; if [ -f "$f" ]; then echo "TAIL_BEGIN path=$f bytes=$(stat -c %s "$f")"; tail -n "$n" "$f"; echo "TAIL_END path=$f"; else echo "FILE_ABSENT path=$f"; fi; }
echo "=== ACCOUNTING ==="
timeout 30s sacct -n -P -j 226763 --format=JobIDRaw,JobName%32,State,ExitCode,ElapsedRaw,AllocCPUS,AllocTRES%40,NodeList,Submit,Start,End 2>&1
echo "=== QUEUE ==="
timeout 25s squeue -u "$USER" -h -o '%i|%T|%P|%R|%S|%C|%b|%M|%j' 2>&1 | grep kdpp3 ; true
echo "=== HGPU4_GRES_USED ==="
timeout 25s sinfo -p hgpu4 -N -O nodelist,gresused:24 2>&1
echo "=== REQUEST unseal_a_seq179 ==="
for f in $ROOT/runtime/unseal_a_seq179/slurm-*.stdout; do [ -f "$f" ] && tail_file "$f" 40; done; true
for f in $ROOT/runtime/unseal_a_seq179/slurm-*.stderr; do [ -f "$f" ] && tail_file "$f" 20; done; true
emit_json $ROOT/runtime/unseal_a_seq179/logs/pool_result.json
for f in $ROOT/runtime/unseal_a_seq179/logs/*.stderr; do [ -f "$f" ] && [ -s "$f" ] && tail_file "$f" 15; done; true
echo "=== ANALYSIS analysis/unseal_a/basin_01435000.json ==="; emit_json $ROOT/analysis/unseal_a/basin_01435000.json
echo "=== ANALYSIS analysis/unseal_a/basin_01440400.json ==="; emit_json $ROOT/analysis/unseal_a/basin_01440400.json
echo "=== ANALYSIS analysis/unseal_a/basin_01487000.json ==="; emit_json $ROOT/analysis/unseal_a/basin_01487000.json
echo "=== ANALYSIS analysis/unseal_a/basin_02092500.json ==="; emit_json $ROOT/analysis/unseal_a/basin_02092500.json
echo "=== ANALYSIS analysis/unseal_a/basin_02102908.json ==="; emit_json $ROOT/analysis/unseal_a/basin_02102908.json
echo "=== ANALYSIS analysis/unseal_a/basin_02178400.json ==="; emit_json $ROOT/analysis/unseal_a/basin_02178400.json
echo "=== ANALYSIS analysis/unseal_a/basin_03049000.json ==="; emit_json $ROOT/analysis/unseal_a/basin_03049000.json
echo "=== ANALYSIS analysis/unseal_a/basin_03076600.json ==="; emit_json $ROOT/analysis/unseal_a/basin_03076600.json
echo "=== ANALYSIS analysis/unseal_a/basin_04027000.json ==="; emit_json $ROOT/analysis/unseal_a/basin_04027000.json
echo "=== ANALYSIS analysis/unseal_a/basin_04105700.json ==="; emit_json $ROOT/analysis/unseal_a/basin_04105700.json
echo "=== ANALYSIS analysis/unseal_a/basin_05503800.json ==="; emit_json $ROOT/analysis/unseal_a/basin_05503800.json
echo "=== ANALYSIS analysis/unseal_a/basin_06803510.json ==="; emit_json $ROOT/analysis/unseal_a/basin_06803510.json
echo "=== ANALYSIS analysis/unseal_a/basin_08070200.json ==="; emit_json $ROOT/analysis/unseal_a/basin_08070200.json
echo "=== ANALYSIS analysis/unseal_a/basin_08086290.json ==="; emit_json $ROOT/analysis/unseal_a/basin_08086290.json
echo "=== ANALYSIS analysis/unseal_a/basin_08109700.json ==="; emit_json $ROOT/analysis/unseal_a/basin_08109700.json
echo "=== ANALYSIS analysis/unseal_a/basin_08190500.json ==="; emit_json $ROOT/analysis/unseal_a/basin_08190500.json
echo "=== ANALYSIS analysis/unseal_a/basin_09035800.json ==="; emit_json $ROOT/analysis/unseal_a/basin_09035800.json
echo "=== ANALYSIS analysis/unseal_a/basin_09513780.json ==="; emit_json $ROOT/analysis/unseal_a/basin_09513780.json
echo "=== ANALYSIS analysis/unseal_a/basin_12175500.json ==="; emit_json $ROOT/analysis/unseal_a/basin_12175500.json
echo "=== ANALYSIS analysis/unseal_a/basin_12447390.json ==="; emit_json $ROOT/analysis/unseal_a/basin_12447390.json
echo "=== ANALYSIS analysis/unseal_a/basin_14185900.json ==="; emit_json $ROOT/analysis/unseal_a/basin_14185900.json
echo "=== ANALYSIS analysis/unseal_a_summary.log ==="; emit_json $ROOT/analysis/unseal_a_summary.log
echo "=== FULL_STDOUT unseal_a_seq179 ==="; for f in $ROOT/runtime/unseal_a_seq179/slurm-*.stdout; do [ -f "$f" ] && { echo "FULL_BEGIN path=$f bytes=$(stat -c %s "$f")"; cat "$f"; echo "FULL_END path=$f"; }; done; true
echo "READ_ONLY_OBSERVE_COMPLETE submissions=0 cancellations=0 modifications=0"
