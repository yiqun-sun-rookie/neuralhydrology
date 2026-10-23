#!/bin/bash
# USER_AUTHORIZED_NICE_2 2026-10-23: same authorization; 246450 array (task 0 running, 1-4 pending) nice=100000 - nice only changes scheduling order of pending tasks, does not touch the running task
echo "NC2_TIME $(date -u +%FT%TZ)"
scontrol update jobid=246450 nice=100000 2>&1; echo "NC2_RC $?"
sleep 5
squeue -j 246349,246450,241337,241344 -h -o "%i|%j|%T|%Q|%y" 2>&1
exit 0
