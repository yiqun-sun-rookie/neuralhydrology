#!/bin/bash
set -eo pipefail
export TZ=UTC
hostname
date -u '+%Y-%m-%dT%H:%M:%SZ'
squeue -u sunyiq -h -o '%i|%j|%T|%M|%R'
sinfo -p hgpu4 -N -h -o '%N|%T|%m|%C'
if [ -e '/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_step3_replay_20261020_001' ]; then echo OWN_TARGET_ALREADY_EXISTS; exit 13; fi
test -f /data1/home/sunyiq/knet_camels_hpc_20261012_001/template/bundle_manifest.json
sha256sum /data1/home/sunyiq/knet_camels_hpc_20261012_001/template/bundle_manifest.json
test -f /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_scratch_20261017_001/runs/02092500/attempt_001/state_constrained/proposal_003.npz
echo OWN_TARGET_ABSENT_AND_ARCHIVED_INPUT_PRESENT
