#!/bin/bash
# kalmannet-daily-perbasin sequence=159: READ-ONLY observation (zero_gain). No sbatch, no scancel, no writes.
set -o pipefail
echo "channel=kalmannet-daily-perbasin sequence=159 purpose=observe-zero_gain"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
emit_json() { f="$1"; if [ -f "$f" ]; then echo "JSON_BEGIN path=$f bytes=$(stat -c %s "$f") sha256=$(sha256sum "$f" | cut -c1-64)"; cat "$f"; echo; echo "JSON_END path=$f"; else echo "FILE_ABSENT path=$f"; fi; }
tail_file() { f="$1"; n="$2"; if [ -f "$f" ]; then echo "TAIL_BEGIN path=$f bytes=$(stat -c %s "$f")"; tail -n "$n" "$f"; echo "TAIL_END path=$f"; else echo "FILE_ABSENT path=$f"; fi; }
echo "=== ACCOUNTING ==="
timeout 30s sacct -n -P -j 226297 --format=JobIDRaw,JobName%32,State,ExitCode,ElapsedRaw,AllocCPUS,AllocTRES%40,NodeList,Submit,Start,End 2>&1
echo "=== QUEUE ==="
timeout 25s squeue -u "$USER" -h -o '%i|%T|%P|%R|%S|%C|%b|%M|%j' 2>&1 | grep kdpp3 ; true
echo "=== HGPU4_GRES_USED ==="
timeout 25s sinfo -p hgpu4 -N -O nodelist,gresused:24 2>&1
echo "=== REQUEST zero_gain_probe4_seq158 ==="
for f in $ROOT/runtime/zero_gain_probe4_seq158/slurm-*.stdout; do [ -f "$f" ] && tail_file "$f" 40; done; true
for f in $ROOT/runtime/zero_gain_probe4_seq158/slurm-*.stderr; do [ -f "$f" ] && tail_file "$f" 20; done; true
emit_json $ROOT/runtime/zero_gain_probe4_seq158/logs/pool_result.json
for f in $ROOT/runtime/zero_gain_probe4_seq158/logs/*.stderr; do [ -f "$f" ] && [ -s "$f" ] && tail_file "$f" 15; done; true
echo "=== FULL_STDOUT zero_gain_probe4_seq158 ==="; for f in $ROOT/runtime/zero_gain_probe4_seq158/slurm-*.stdout; do [ -f "$f" ] && { echo "FULL_BEGIN path=$f bytes=$(stat -c %s "$f")"; cat "$f"; echo "FULL_END path=$f"; }; done; true
echo "READ_ONLY_OBSERVE_COMPLETE submissions=0 cancellations=0 modifications=0"
