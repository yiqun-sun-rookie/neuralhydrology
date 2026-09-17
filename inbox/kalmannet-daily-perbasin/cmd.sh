#!/bin/bash
# kalmannet-daily-perbasin sequence=150: READ-ONLY observation (phase_a). No sbatch, no scancel, no writes.
set -o pipefail
echo "channel=kalmannet-daily-perbasin sequence=150 purpose=observe-phase_a"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
emit_json() { f="$1"; if [ -f "$f" ]; then echo "JSON_BEGIN path=$f bytes=$(stat -c %s "$f") sha256=$(sha256sum "$f" | cut -c1-64)"; cat "$f"; echo; echo "JSON_END path=$f"; else echo "FILE_ABSENT path=$f"; fi; }
tail_file() { f="$1"; n="$2"; if [ -f "$f" ]; then echo "TAIL_BEGIN path=$f bytes=$(stat -c %s "$f")"; tail -n "$n" "$f"; echo "TAIL_END path=$f"; else echo "FILE_ABSENT path=$f"; fi; }
echo "=== ACCOUNTING ==="
timeout 30s sacct -n -P -j 226233 --format=JobIDRaw,JobName%32,State,ExitCode,ElapsedRaw,AllocCPUS,AllocTRES%40,NodeList,Submit,Start,End 2>&1
timeout 30s sacct -n -P -j 226234 --format=JobIDRaw,JobName%32,State,ExitCode,ElapsedRaw,AllocCPUS,AllocTRES%40,NodeList,Submit,Start,End 2>&1
timeout 30s sacct -n -P -j 226235 --format=JobIDRaw,JobName%32,State,ExitCode,ElapsedRaw,AllocCPUS,AllocTRES%40,NodeList,Submit,Start,End 2>&1
echo "=== QUEUE ==="
timeout 25s squeue -u "$USER" -h -o '%i|%T|%P|%R|%S|%C|%b|%M|%j' 2>&1 | grep kdpp3 ; true
echo "=== HGPU4_GRES_USED ==="
timeout 25s sinfo -p hgpu4 -N -O nodelist,gresused:24 2>&1
echo "=== REQUEST phase_a_node0_seq146 ==="
for f in $ROOT/runtime/phase_a_node0_seq146/slurm-*.stdout; do [ -f "$f" ] && tail_file "$f" 40; done; true
for f in $ROOT/runtime/phase_a_node0_seq146/slurm-*.stderr; do [ -f "$f" ] && tail_file "$f" 20; done; true
emit_json $ROOT/runtime/phase_a_node0_seq146/logs/pool_result.json
for f in $ROOT/runtime/phase_a_node0_seq146/logs/*.stderr; do [ -f "$f" ] && [ -s "$f" ] && tail_file "$f" 15; done; true
echo "=== REQUEST phase_a_node1_seq147 ==="
for f in $ROOT/runtime/phase_a_node1_seq147/slurm-*.stdout; do [ -f "$f" ] && tail_file "$f" 40; done; true
for f in $ROOT/runtime/phase_a_node1_seq147/slurm-*.stderr; do [ -f "$f" ] && tail_file "$f" 20; done; true
emit_json $ROOT/runtime/phase_a_node1_seq147/logs/pool_result.json
for f in $ROOT/runtime/phase_a_node1_seq147/logs/*.stderr; do [ -f "$f" ] && [ -s "$f" ] && tail_file "$f" 15; done; true
echo "=== REQUEST phase_a_node2_seq148 ==="
for f in $ROOT/runtime/phase_a_node2_seq148/slurm-*.stdout; do [ -f "$f" ] && tail_file "$f" 40; done; true
for f in $ROOT/runtime/phase_a_node2_seq148/slurm-*.stderr; do [ -f "$f" ] && tail_file "$f" 20; done; true
emit_json $ROOT/runtime/phase_a_node2_seq148/logs/pool_result.json
for f in $ROOT/runtime/phase_a_node2_seq148/logs/*.stderr; do [ -f "$f" ] && [ -s "$f" ] && tail_file "$f" 15; done; true
for d in $ROOT/runs/*; do [ -d "$d" ] || continue; if [ -f "$d/completion.marker.json" ]; then echo "=== RUN $d ==="; emit_json "$d/completion.marker.json"; else rows=$( [ -f "$d/epoch_history.json" ] && grep -c '"epoch_status"' "$d/epoch_history.json" || echo 0 ); lock=$( [ -f "$d/running.lock.json" ] && echo yes || echo no ); age=$( [ -f "$d/checkpoints/last.pt" ] && echo $(( $(date +%s) - $(stat -c %Y "$d/checkpoints/last.pt") )) || echo none ); echo "RUN_PROGRESS path=$d rows=$rows lock=$lock last_pt_age_s=$age"; fi; done; true
for d in $ROOT/runs/*_KNET_BASIN_01487000_SEED_20260824; do [ -d "$d" ] || continue; echo "=== LEDGER $d ==="; emit_json "$d/epoch_history.json"; emit_json "$d/result_summary.json"; done; true
for d in $ROOT/runs/*_KNET_BASIN_02178400_SEED_20260824; do [ -d "$d" ] || continue; echo "=== LEDGER $d ==="; emit_json "$d/epoch_history.json"; emit_json "$d/result_summary.json"; done; true
for d in $ROOT/runs/*_KNET_BASIN_03076600_SEED_20260824; do [ -d "$d" ] || continue; echo "=== LEDGER $d ==="; emit_json "$d/epoch_history.json"; emit_json "$d/result_summary.json"; done; true
for d in $ROOT/runs/*_KNET_BASIN_06803510_SEED_20260824; do [ -d "$d" ] || continue; echo "=== LEDGER $d ==="; emit_json "$d/epoch_history.json"; emit_json "$d/result_summary.json"; done; true
for d in $ROOT/runs/*_KNET_BASIN_08086290_SEED_20260824; do [ -d "$d" ] || continue; echo "=== LEDGER $d ==="; emit_json "$d/epoch_history.json"; emit_json "$d/result_summary.json"; done; true
for d in $ROOT/runs/*_KNET_BASIN_12447390_SEED_20260824; do [ -d "$d" ] || continue; echo "=== LEDGER $d ==="; emit_json "$d/epoch_history.json"; emit_json "$d/result_summary.json"; done; true
echo "READ_ONLY_OBSERVE_COMPLETE submissions=0 cancellations=0 modifications=0"
