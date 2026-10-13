#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/knet_camels_hpc_20261012_001
test -d "$ROOT/attempts"
test -f "$ROOT/template/safe_io.py"
cat "$ROOT/OWNER.txt"
date -u '+%Y-%m-%dT%H:%M:%SZ'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%N|%R'
sinfo -p hgpu4 -N -O nodelist,cpusstate
sacct -j 241332 --noheader --parsable2 --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,Partition,NodeList
