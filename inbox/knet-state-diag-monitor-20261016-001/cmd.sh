#!/bin/bash
set -eo pipefail
hostname
date -u +%Y-%m-%dT%H:%M:%SZ
pgrep -afu sunyiq 'hpc_runner_active' || true
squeue -u sunyiq -h -o '%i|%j|%T|%M|%R'
