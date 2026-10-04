#!/usr/bin/env bash
set -eo pipefail
task_base="$HOME/hpc_mailbox/inbox/precip-dynamic-filter-v03/payload"
task_deploy="$task_base/eight_basin_fixed_recipe_v01_20261003_230000_d5028d71_deploy_v02.sh"
test -f "$task_deploy"
task_actual=$(sha256sum "$task_deploy")
task_actual=${task_actual%% *}
test "$task_actual" = "5fc893cc94056a0531c5bd79a172bf6f04d5bfbdcb72b565cf319768c676651c"
bash "$task_deploy" "$task_base/eight_basin_fixed_recipe_v01_20261003_230000_d5028d71_payload_v02.tgz" "d5d7d6ff334d4ca31c576b050a2c2e0a7638e6b9bc7b02fb9875c569d33e1150" "3361652273484e838adea7682ae679b15738198da6a5e542c71d5fab173187a3" "$HOME/precip_dynamic_eight_basins_20261003/eight_basin_fixed_recipe_v01_20261003_230000_d5028d71" "/data1/home/sunyiq/neuralhydrology/data/camels_us" "/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python" "$task_base/eight_basin_fixed_recipe_v01_20261003_230000_d5028d71_validator_v02.py" "b564539080b6ab7c53d3f4938ed6749e617ce4e11fb0e62cbb8e343078f032c1"
