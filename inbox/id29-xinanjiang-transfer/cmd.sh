#!/bin/bash
# Read-only preflight after the sequence-18 deployment guard failure.
set -eo pipefail
RECOVERY=/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01_recovery_01
date -Is
if test -e "$RECOVERY"; then
  printf 'RECOVERY_ROOT_EXISTS\n'
  find "$RECOVERY" -maxdepth 2 -type f -printf '%P\n' | sort
else
  printf 'RECOVERY_ROOT_ABSENT\n'
fi
printf 'MATCHING_ACTIVE_JOBS\n'
squeue -h -o '%i|%j|%T' | awk -F '|' '$2 == "id29-xaj-rec2" {print}'
printf 'MATCHING_ACCOUNTING_ROWS\n'
sacct -S 2026-09-08T13:55:00 -n -P --format=JobIDRaw,JobName,State,ExitCode,Submit,Start,End | \
  awk -F '|' '$2 == "id29-xaj-rec2" {print}'
printf 'RECOVERY_ABSENCE_CHECK_COMPLETE\n'
