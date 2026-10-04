#!/bin/bash
set -eo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B /data1/home/sunyiq/kalmannet_tukf09_four_failed_basins_20261003_attempt1/remote_stage.py admit 02297310 --audit-sha 91d51e78cf543cdfed5d8e514a2734b2f69e3977a2015df3b765199edfd38187 --capture-sha 21ad3f1f1fcd335be8811842e6bf3b7bbbb8d657fe9d9464ce4c57096cf23c77
