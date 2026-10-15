#!/bin/bash
set -o pipefail
# seq 4: unpack payload v1 into OWN root, then start the data build in the background (network I/O only)
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
P="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v1"
date --iso-8601=seconds
for f in build_data.py attrs_531.tar.gz smoke.yml native531.yml run_ohn.slurm; do
  [ -f "$P/$f" ] || { echo "MISSING_PAYLOAD $f"; exit 1; }
done
mkdir -p "$ROOT/attrs" "$ROOT/configs" "$ROOT/logs"
tar -xzf "$P/attrs_531.tar.gz" -C "$ROOT/attrs" && ls -la "$ROOT/attrs"
cp "$P/build_data.py" "$ROOT/src/build_data.py"
cp "$P/smoke.yml" "$P/native531.yml" "$ROOT/configs/"
cp "$P/run_ohn.slurm" "$ROOT/run_ohn.slurm"
sed -i 's/\r$//' "$ROOT/src/build_data.py" "$ROOT/configs/smoke.yml" "$ROOT/configs/native531.yml" "$ROOT/run_ohn.slurm"
sha256sum "$ROOT/src/build_data.py" "$ROOT/run_ohn.slurm" "$ROOT/configs/smoke.yml" "$ROOT/configs/native531.yml"
LIST="$ROOT/src/flood-forecasting/example-configs/camels-us-531-basins-list.txt"
tr -s ' \n' '\n\n' < "$LIST" | grep -c . | sed 's/^/basins in list: /'
tr -s ' \n' '\n\n' < "$LIST" | grep . | head -8 > "$ROOT/data/smoke_basins.txt"
cat "$ROOT/data/smoke_basins.txt" | tr '\n' ' '; echo
if pgrep -f "openhydronet_531_20261015/src/build_data.py" > /dev/null; then echo "BUILD ALREADY RUNNING"; exit 0; fi
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite:$ROOT/src/flood-forecasting"
tr -s ' \n' '\n\n' < "$LIST" | grep . > "$ROOT/data/basins_531.txt"
cd "$ROOT"
nohup setsid python -u "$ROOT/src/build_data.py" "$ROOT" "$ROOT/data/basins_531.txt" "$ROOT/attrs" > "$ROOT/logs/build_data.log" 2>&1 < /dev/null &
sleep 3
pgrep -af "openhydronet_531_20261015/src/build_data.py" | head -2
tail -3 "$ROOT/logs/build_data.log"
exit 0
