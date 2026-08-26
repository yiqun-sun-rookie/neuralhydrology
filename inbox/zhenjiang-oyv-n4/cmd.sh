#!/bin/bash
# Identify the cards on the idle hgpu8 nodes. sinfo never names the model, so the
# only way to know is to run something on them.
set -o pipefail

echo "=== A. THE EXISTING NODE TEST LAUNCHER ==="
sed -n '1,25p' /data1/home/sunyiq/hpc_mailbox/inbox/node_test.slurm 2>&1 || echo "  unreadable"

echo "=== B. SUBMIT PROBES TO THE IDLE hgpu8 NODES ==="
cd /data1/home/sunyiq/hpc_mailbox || exit 1
IDS=""
for n in ngu201 ngu203 ngu202; do
  out=$(sbatch --parsable -p hgpu8 --nodelist="$n" --job-name="nt_$n" -t 00:05:00 inbox/node_test.slurm 2>&1)
  jid=$(echo "$out" | grep -oE '^[0-9]+' || true)
  if [ -n "$jid" ]; then echo "  $n -> job $jid"; IDS="$IDS $jid"; else echo "  $n -> SUBMIT FAILED: $out"; fi
done
[ -n "$IDS" ] || { echo "NO_PROBE_SUBMITTED"; exit 1; }

echo "=== C. WAIT (max 4 min; these nodes are idle so it should be quick) ==="
for i in $(seq 1 24); do
  LEFT=0
  for j in $IDS; do
    st=$(sacct -j "$j" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
    case "$st" in RUNNING|PENDING|"") LEFT=$((LEFT+1));; esac
  done
  [ "$LEFT" -eq 0 ] && { echo "  all settled at t=$((i*10))s"; break; }
  sleep 10
done

echo "=== D. PROBE RESULTS ==="
for j in $IDS; do
  echo "  ---- job $j ----"
  sacct -j "$j" -X --format=JobID%10,JobName%10,NodeList%9,State%12,ExitCode%8,Elapsed%9 2>&1 | tail -2
  for f in /data1/home/sunyiq/hpc_mailbox/outbox/slurm_${j}.out /data1/home/sunyiq/hpc_mailbox/outbox/node_test_${j}.out; do
    [ -f "$f" ] && { echo "    -- $f --"; sed -n '1,30p' "$f" | sed 's/^/      /'; }
  done
done

echo "=== E. CLEAN UP ONLY MY OWN PROBE LOGS ==="
for j in $IDS; do rm -f "/data1/home/sunyiq/hpc_mailbox/outbox/slurm_${j}.out" "/data1/home/sunyiq/hpc_mailbox/outbox/slurm_${j}.err"; done
echo "  done"

echo "=== F. DONE ==="
