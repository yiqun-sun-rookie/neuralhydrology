#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-graice-matched-20261016/payload/graice_author_matched_b04_payload_v001.tar.gz
if [ -e "$root" ]; then echo EXISTING_ROOT_NO_OVERWRITE; exit 1; fi
if [ -n "$(squeue -h -u sunyiq -n id25_graice_m_261016 -o '%i')" ]; then echo ACTIVE_OWN_JOB_NO_DUPLICATE; exit 1; fi
printf '%s  %s\n' '844e948c2fa1752c7a37b32d622c4d44c55d40c0ff1174116a2dc0344562ef15' "$payload" | sha256sum -c -
mkdir -p "$root/logs" "$root/artifacts" "$root/inputs"
tar -xzf "$payload" -C "$root"
cp /data1/home/sunyiq/id25_regional_daily_storage_20261012_001/inputs/inputs.npz "$root/inputs/inputs.npz"
printf '%s  %s\n' 'b6e20598038eccf7a18753619342fdd48e90990f4cde4685eef42929978f2566' "$root/inputs/inputs.npz" | sha256sum -c -
echo B04_DEPLOYED_NO_JOB_SUBMITTED
