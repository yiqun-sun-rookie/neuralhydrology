#!/bin/bash
set -eo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B /data1/home/sunyiq/kalmannet_tukf09_four_failed_basins_20261003_attempt1/remote_stage.py admit 01139000 --audit-sha 63978fb74bd84f06441f6575fdd48d0034dc9ff086d9be27d3eab2dadbc85f23 --capture-sha 68c9617a8ca668f648ff7a48233a966a148aec74881137e7c1fabb423ff838e0
