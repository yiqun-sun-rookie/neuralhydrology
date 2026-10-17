#!/bin/bash
set -u
root=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
test "$(cat "$root/job_id.txt")" = 244024 || exit 2
probe() {
  printf '\nQUERY: %s\n' "$*"
  "$@"
  result=$?
  printf 'QUERY_EXIT_CODE=%s\n' "$result"
}
probe date -Iseconds
probe cat "$root/job_id.txt" "$root/submissions.tsv"
probe scontrol -d show job 244024
probe squeue -j 244024 --start -o '%i|%T|%r|%S|%V|%Q|%l|%P|%R'
probe sprio -l -j 244024
probe sshare -l -u sunyiq
for partition in hgpu2p hgpu2 hgpu4 hgpu8; do
  probe scontrol show partition "$partition"
done
probe sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -O 'partition:12,nodelist:16,gres:16,gresused:28,cpusstate:22'
probe sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -o '%P|%N|%t|%E'
probe squeue -u sunyiq -p hgpu2p,hgpu2,hgpu4,hgpu8 -o '%i|%j|%T|%Q|%S|%l|%D|%R'
for name in status.json interface_check.json runtime.json; do
  if [ -f "$root/$name" ]; then probe cat "$root/$name"; fi
done
exit 0
