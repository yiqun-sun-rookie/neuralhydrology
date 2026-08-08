#!/bin/bash
# Set up an isolated ID17 workspace. Does NOT touch ~/neuralhydrology (78 dirty files there).
set -o pipefail
D=~/id17_film_gate

echo "=== A. CLONE (branch hpc/id17-film-gate) ==="
if [ -d "$D/.git" ]; then
  cd "$D" && git fetch -q origin "+hpc/id17-film-gate:refs/remotes/origin/hpc/id17-film-gate" 2>&1 | tail -2 \
    && git reset -q --hard refs/remotes/origin/hpc/id17-film-gate && echo "updated existing clone"
else
  git clone -q --depth 1 --branch hpc/id17-film-gate --single-branch \
    git@github.com:yiqun-sun-rookie/neuralhydrology.git "$D" 2>&1 | tail -3 && echo "cloned"
fi
cd "$D" || exit 1
git log --oneline -1

echo "=== B. LINK DATA (read-only reuse, no copy) ==="
[ -e "$D/data" ] || ln -s ~/neuralhydrology/data "$D/data"
ls -ld "$D/data"
ls "$D/data/camels_us/basin_mean_forcing/" 2>&1 | head -5
echo "daymet basins: $(find $D/data/camels_us/basin_mean_forcing/daymet -name '*_forcing_leap.txt' 2>/dev/null | wc -l)"
echo "streamflow files: $(find $D/data/camels_us/usgs_streamflow -name '*_streamflow_qc.txt' 2>/dev/null | wc -l)"
ls "$D/data/camels_us/camels_attributes_v2.0/" 2>&1 | head -5

echo "=== C. FOLD BASIN FILES ==="
wc -l src/static_falsification/data/fold*_train.txt src/static_falsification/data/fold0_test.txt 2>&1 | tail -8

echo "=== D. FIX CRLF + MAKE LOG DIRS ==="
sed -i 's/\r$//' src/static_falsification/hpc/*.slurm
mkdir -p logs/17_entity_awareness_hypernet results/17_entity_awareness_hypernet
file src/static_falsification/hpc/smoke_gate.slurm

echo "=== E. GENERATE CONFIGS (lightweight, login-node safe) ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>&1 >/dev/null
python src/static_falsification/hpc/gen_configs.py 2>&1 | head -3
ls src/static_falsification/configs/hpc_gate/ | wc -l

echo "=== F. IMPORT CHECK (no compute) ==="
python -c "
import sys; sys.path.insert(0,'.')
from neuralhydrology.modelzoo.filmlstm import FiLMLSTM
from neuralhydrology.utils.config import Config
c = Config({'model':'filmlstm','film_site':'input','head':'regression','hidden_size':8,
            'dynamic_inputs':['prcp(mm/day)'],'static_attributes':['elev_mean'],
            'target_variables':['QObs(mm/d)'],'film_generator_hidden_size':4,
            'initial_forget_bias':3,'output_dropout':0.0,'output_activation':'linear'})
print('film_site =', c.film_site, '| FiLMLSTM importable OK')" 2>&1 | tail -3

echo "=== G. DISK USE ==="
du -sh "$D" 2>/dev/null; df -h /data1 | tail -1
