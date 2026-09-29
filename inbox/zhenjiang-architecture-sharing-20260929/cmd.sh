#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/zhenjiang_architecture_sharing_20260929_001
printf '=== exclusive root ===\n'
if [ -e "$root" ] || [ -L "$root" ]; then
  printf 'ROOT_OCCUPIED\n'
  timeout 10 stat -c 'type=%F owner=%U mode=%a path=%n' -- "$root"
else
  printf 'ROOT_ABSENT\n'
fi
printf '=== intended GPU partition ===\n'
timeout 15 scontrol show partition hgpu2p -o | cut -c1-700
printf '=== GPU node states ===\n'
timeout 15 sinfo -h -p hgpu2p -o '%N|%T|%G' | sed -n '1,20p'
printf '=== own scheduling load ===\n'
timeout 15 squeue -h -u sunyiq -o '%i|%T|%P|%j' | sed -n '1,20p'
