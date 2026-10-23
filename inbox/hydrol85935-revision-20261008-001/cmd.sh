#!/bin/bash
# USER_AUTHORIZED_NICE 2026-10-23: lower priority of pending 246349 and 246450 (nice=100000) so 241337/241344 start first; touches nothing else
echo "NC_TIME $(date -u +%FT%TZ)"
echo "NC_BEFORE"; squeue -j 246349,246450,241337,241344 -h -o "%i|%j|%T|%Q|%y" 2>&1
for J in 246349 246450; do S=$(squeue -j $J -h -o "%T" 2>/dev/null | sort -u | tr "\n" ","); echo "NC_STATE $J $S"; case "$S" in PENDING,) scontrol update jobid=$J nice=100000 2>&1; echo "NC_RC $J $?";; *) echo "NC_SKIP $J not purely pending";; esac; done
sleep 5
echo "NC_AFTER"; squeue -j 246349,246450,241337,241344 -h -o "%i|%j|%T|%Q|%y" 2>&1
sprio -j 246349,246450,241337,241344 -h 2>&1 | head -12
exit 0
