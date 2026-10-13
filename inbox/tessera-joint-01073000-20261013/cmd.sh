#!/bin/bash
set -eo pipefail
date -u
hostname
id -un
squeue -u sunyiq -o '%.18i %.12P %.32j %.10T %.10M %.6D %R'
sinfo -p hgpu2p,hgpu4,hgpu8 -N -O nodelist,partition,statecompact,gres,gresused
df -h /data1/home/sunyiq
ROOT=/data1/home/sunyiq/tessera_joint_01073000_20261013_001
if [ -e "$ROOT" ]; then echo ROOT_ALREADY_EXISTS; else echo ROOT_AVAILABLE; fi
test -w /data1/home/sunyiq
test -f /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
test -x /usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch
for f in /data1/home/sunyiq/neuralhydrology/results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/model_epoch030.pt /data1/home/sunyiq/neuralhydrology/external/tessera_v2_small_9e1a725/ckpt/student_small.pt; do
  if [ -f "$f" ]; then sha256sum "$f"; else echo "NOT_PRESENT $f"; fi
done
echo PREFLIGHT_COMPLETE
