#!/bin/bash
set -u
root=/data1/home/sunyiq/id25_graice_shared_probe_20261019_001
old=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
probe() { printf '\nQUERY: %s\n' "$*"; timeout 40 "$@"; result=$?; printf 'QUERY_EXIT_CODE=%s\n' "$result"; }
probe date -Iseconds
probe id -un
if [ -e "$root" ]; then printf 'NEW_ROOT_ALREADY_EXISTS\n'; ls -ld "$root"; else printf 'NEW_ROOT_UNUSED\n'; fi
probe squeue -h -u sunyiq -n id25_c01_probe_261019 -o '%i|%j|%T|%P|%R'
probe sacct -X -S 2026-10-18 -u sunyiq --name=id25_c01_probe_261019 --format=JobIDRaw,JobName,Account,Partition,State,ExitCode -n -P
probe sacctmgr -n -P show assoc user=sunyiq account=g_sunyiq format=Cluster,Account,User,Partition,QOS
probe scontrol show partition hgpu2p
probe sinfo -p hgpu2p -N -O 'nodelist:16,gres:16,gresused:28,cpusstate:22'
if [ -x "$old/venv/bin/python" ] && [ -f "$old/venv/runtime_ready" ]; then printf 'EXISTING_B04_RUNTIME_FILES_PRESENT\n'; else printf 'EXISTING_B04_RUNTIME_NOT_READY\n'; fi
for file in "$old/inputs/inputs.npz" "$old/runs/lat+026_lon-082/scalers.json"; do if [ -r "$file" ]; then printf 'READABLE=%s\n' "$file"; else printf 'UNREADABLE=%s\n' "$file"; fi; done
printf 'NO_SCIENTIFIC_COMPUTE_NO_SUBMISSION_NO_PAYMENT_ACTION\n'
exit 0
