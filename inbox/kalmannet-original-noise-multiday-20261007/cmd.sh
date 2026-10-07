#!/bin/bash
set -eo pipefail
umask 027
phase='/data1/home/sunyiq/kalmannet_original_noise_multiday_20261007_attempt1'
archive="$HOME/hpc_mailbox/inbox/kalmannet-original-noise-multiday-20261007/payload/original_noise_multiday_v4.tar.gz"
test ! -e "$phase"
printf '%s  %s\n' '2ea95b2f8cf12918d8e82bae0967d5b059d727997da303a695b16b9dd951112e' "$archive" | sha256sum -c -
mkdir "$phase"
tar -xzf "$archive" -C "$phase" --no-same-owner --no-same-permissions
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -X utf8 -B "$phase/code/remote.py" check
