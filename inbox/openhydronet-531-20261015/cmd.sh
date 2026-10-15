#!/bin/bash
set -o pipefail
# seq 19: install payload v3 into own root and start the ID18-protocol data build in the background (low priority, read-only on ~/neuralhydrology)
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
P2="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v2"
P3="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v3"
date --iso-8601=seconds
for f in "$P3/build_id18_data.py" "$P3/id18_cmal.yml" "$P3/id18_nse.yml" "$P2/conceptual_benchmark_camels_us_531_repro.txt"; do [ -f "$f" ] || { echo "MISSING $f"; exit 1; }; done
cp "$P3/build_id18_data.py" "$ROOT/src/build_id18_data.py"
cp "$P3/id18_cmal.yml" "$P3/id18_nse.yml" "$ROOT/configs/"
tr -s ' \n' '\n\n' < "$P2/conceptual_benchmark_camels_us_531_repro.txt" | grep . > "$ROOT/data/id18_basins_531.txt"
sed -i 's/\r$//' "$ROOT/src/build_id18_data.py" "$ROOT/configs/id18_cmal.yml" "$ROOT/configs/id18_nse.yml" "$ROOT/data/id18_basins_531.txt"
wc -l "$ROOT/data/id18_basins_531.txt"
sha256sum "$ROOT/src/build_id18_data.py" "$ROOT/configs/id18_cmal.yml" "$ROOT/configs/id18_nse.yml" | cut -c1-16,65-
if [ -e "$ROOT/data/id18_maurer/dynamics" ]; then echo "id18_maurer already exists - not rebuilding"; exit 0; fi
if pgrep -f "src/build_id18_data.py" > /dev/null; then echo "BUILD ALREADY RUNNING"; exit 0; fi
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite"
cd "$ROOT"
nohup setsid nice -n 19 python -u "$ROOT/src/build_id18_data.py" "$HOME/neuralhydrology/data/camels_us" "$ROOT/data/id18_basins_531.txt" "$ROOT/data/id18_maurer" > "$ROOT/logs/build_id18.log" 2>&1 < /dev/null &
sleep 4
pgrep -af "src/build_id18_data.py" | head -2 | cut -c1-160
tail -3 "$ROOT/logs/build_id18.log"
exit 0
