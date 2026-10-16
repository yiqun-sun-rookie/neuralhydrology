#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
if [ -f "$root/job_id.txt" ]; then
  jid=$(cat "$root/job_id.txt")
  printf 'JOB_ID=%s\n' "$jid"
  cat "$root/submissions.tsv"
  squeue -h -u sunyiq -n id25_graice_m_261016 -o '%i|%j|%T|%M|%R'
  sacct -j "$jid" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList -n -P
  for file in "$root/logs/b04-$jid.out" "$root/logs/b04-$jid.err"; do
    if [ -f "$file" ]; then printf '\nLOG=%s\n' "$file"; tail -n 16 "$file"; fi
  done
fi
for file in "$root/status.json" "$root/interface_check.json" "$root/runtime.json" "$root/report.json"; do
  if [ -f "$file" ]; then printf '\nFILE=%s\n' "$file"; cat "$file"; fi
done
if [ -f "$root/logs/env_install_v002.log" ]; then tail -n 8 "$root/logs/env_install_v002.log"; fi
if [ -f "$root/env_status_v002.txt" ]; then cat "$root/env_status_v002.txt"; fi
if [ -f "$root/env_pid_v002.txt" ]; then
  pid=$(cat "$root/env_pid_v002.txt")
  if ps -p "$pid" -o pid,etimes,stat,args; then :; else echo ENV_HELPER_NOT_RUNNING; fi
fi
if [ -f "$root/status.json" ]; then
  rid=$("$root/venv/bin/python" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("region_id", ""))' "$root/status.json")
  if [[ "$rid" =~ ^lat[+-][0-9]{3}_lon[+-][0-9]{3}$ ]]; then
    if [ -f "$root/runs/$rid/last.npz" ]; then stat -c '%n|%s|%y' "$root/runs/$rid/last.npz"; fi
    if [ -f "$root/runs/$rid/metrics.jsonl" ]; then tail -n 2 "$root/runs/$rid/metrics.jsonl"; fi
  fi
fi
