#!/bin/bash
set -eo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B /data1/home/sunyiq/kalmannet_tukf09_four_failed_basins_20261003_attempt1/remote_stage.py admit 02108000 --audit-sha f4b49c070c70f25c1e806d825dc882889b3b78a110453cb21221930b61b39d68 --capture-sha 65c555d38aca2e90d01a9cf3ffcd821f028639106f0c490d8e913f70e0e7d910
