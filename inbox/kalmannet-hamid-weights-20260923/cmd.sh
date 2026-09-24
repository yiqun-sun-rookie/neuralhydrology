#!/bin/bash
set -eo pipefail
sequence=13
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf '\nOWN_JOB_INVENTORY\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%C|%R'
printf '\nORIGINAL_WEIGHT_ARRAY\n'
sacct -X -j 227495 -n -P --format=JobID,JobName%30,State,ExitCode,Elapsed,NodeList
printf '\nGPU_RESOURCES\n'
sinfo -p hgpu2p -N -O nodelist,statelong,gres:14,gresused:24,cpusstate
printf '\nSTORAGE\n'
df -h "$root"
printf '\nSOURCE_IDENTITY\n'
sha256sum "$root/formal_package_v2/manifest.json" "$root/formal_package_v2/protocol.json" "$root/formal_attempt_002/HALT.json"
for path in "$root/diagnostic_package_20260924_v1" "$root/diagnostic_20260924_v1" "$root/diagnostic_submission_claim_20260924_v1"; do
 if [ -e "$path" ]; then printf 'DESTINATION_EXISTS=%s\n' "$path"; else printf 'DESTINATION_ABSENT=%s\n' "$path"; fi
done
printf '\nREAD_ONLY_RESOURCE_CHECK_COMPLETE\n'
