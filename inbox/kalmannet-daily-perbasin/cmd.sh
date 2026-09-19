#!/bin/bash
# kalmannet-daily-perbasin sequence=174: READ-ONLY observation (analysis). No sbatch, no scancel, no writes.
set -o pipefail
echo "channel=kalmannet-daily-perbasin sequence=174 purpose=observe-analysis"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
emit_json() { f="$1"; if [ -f "$f" ]; then echo "JSON_BEGIN path=$f bytes=$(stat -c %s "$f") sha256=$(sha256sum "$f" | cut -c1-64)"; cat "$f"; echo; echo "JSON_END path=$f"; else echo "FILE_ABSENT path=$f"; fi; }
tail_file() { f="$1"; n="$2"; if [ -f "$f" ]; then echo "TAIL_BEGIN path=$f bytes=$(stat -c %s "$f")"; tail -n "$n" "$f"; echo "TAIL_END path=$f"; else echo "FILE_ABSENT path=$f"; fi; }
echo "=== ACCOUNTING ==="
timeout 30s sacct -n -P -j 226526 --format=JobIDRaw,JobName%32,State,ExitCode,ElapsedRaw,AllocCPUS,AllocTRES%40,NodeList,Submit,Start,End 2>&1
echo "=== QUEUE ==="
timeout 25s squeue -u "$USER" -h -o '%i|%T|%P|%R|%S|%C|%b|%M|%j' 2>&1 | grep kdpp3 ; true
echo "=== HGPU4_GRES_USED ==="
timeout 25s sinfo -p hgpu4 -N -O nodelist,gresused:24 2>&1
echo "=== REQUEST e8_node_seq172 ==="
for f in $ROOT/runtime/e8_node_seq172/slurm-*.stdout; do [ -f "$f" ] && tail_file "$f" 40; done; true
for f in $ROOT/runtime/e8_node_seq172/slurm-*.stderr; do [ -f "$f" ] && tail_file "$f" 20; done; true
emit_json $ROOT/runtime/e8_node_seq172/logs/pool_result.json
for f in $ROOT/runtime/e8_node_seq172/logs/*.stderr; do [ -f "$f" ] && [ -s "$f" ] && tail_file "$f" 15; done; true
echo "=== DATA_SURVEY (read-only) ==="
timeout 60s find /data1/home/sunyiq -maxdepth 5 -type d -name 'camels_us' 2>/dev/null | head -10
timeout 60s find /data1/home/sunyiq -maxdepth 6 -type f \( -name 'hydroagent_data_loading.py' -o -path '*hydroagent/data_loading.py' \) 2>/dev/null | head -10 | while read f; do echo "LOADER $f sha256=$(sha256sum "$f" | cut -c1-64) bytes=$(stat -c %s "$f")"; done
timeout 60s find /data1/home/sunyiq -maxdepth 5 -type d -name 'basin_mean_forcing' 2>/dev/null | head -5
timeout 60s find /data1/home/sunyiq -maxdepth 4 -type f -name 'tukf06_full_diagonal_common.py' 2>/dev/null | head -5 | while read f; do echo "TUKF06 $f sha256=$(sha256sum "$f" | cut -c1-64)"; done
echo "=== DATA_SURVEY_WIDE (read-only) ==="
timeout 90s find /data1 -maxdepth 3 -type d -iname '*camels*' 2>/dev/null | head -20
timeout 120s find /data1/home/sunyiq -maxdepth 7 -type d \( -iname '*camels*' -o -name 'basin_mean_forcing' -o -name 'usgs_streamflow' \) 2>/dev/null | head -20
timeout 120s find /data1/home/sunyiq -maxdepth 7 -type f -name 'data_loading.py' 2>/dev/null | head -20 | while read f; do echo "LOADER_ANY $f sha256=$(sha256sum "$f" | cut -c1-16)"; done
for d in /data1/share /data1/data /data1/datasets /data1/public /data /share /home/share; do [ -d "$d" ] && { echo "DIR $d"; ls "$d" 2>/dev/null | head -20; }; done; true
echo "=== TUKF06_EVAL_CONFIG_HINTS (read-only, filenames only) ==="
timeout 60s find /data1/home/sunyiq -maxdepth 3 -type f -name 'tukf06_data_fingerprints_v1.json' 2>/dev/null | head -5
timeout 60s grep -rl --include='*.slurm' --include='*.sh' -m1 'data-root\|data_root\|TUKF06_DATA_LOADER_FILE' /data1/home/sunyiq --exclude-dir='*formal*' 2>/dev/null | head -10
echo "READ_ONLY_OBSERVE_COMPLETE submissions=0 cancellations=0 modifications=0"
