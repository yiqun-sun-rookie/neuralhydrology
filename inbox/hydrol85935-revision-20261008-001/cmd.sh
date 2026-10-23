#!/bin/bash
# READ_ONLY_POST_JOBS: state of validate/export jobs after main array; no mutation
echo "PJ_TIME $(date -u +%FT%TZ)"
echo "PJ_SQUEUE"; squeue -j 241337,241344 -h -o "%i|%T|%r|%P|%b|%S|%Q" 2>&1
echo "PJ_SACCT"; sacct -X -j 241337,241344 -n -P -o JobID,State,ExitCode,Elapsed,Start,End,Partition,NodeList 2>&1
echo "PJ_SPRIO"; sprio -j 241337 -h 2>&1 | head -3
P=$(squeue -j 241337 -h -o "%P" 2>/dev/null | head -1); [ -n "$P" ] && { echo "PJ_PART $P"; sinfo -p "$P" -h -o "%n %t %G" 2>&1 | head -20; squeue -p "$P" -t PD -h -o "%i %Q %u" 2>&1 | sort -k2 -nr | head -10; }
exit 0
