#!/bin/bash
# seq 90: GPM-era contract DEPLOY + read-only probe (PREREG_20260927 section 8). Creates the NEW landing dir
# precip_swap4_gpm_daily_2026_09 (aborts if it exists), links attributes (same chain as Stages 2/3), copies the archived
# code from the Stage-3 landing dir (hash-checked; that dir is only read), installs scripts / tables / basin lists from
# the mailbox payload, generates configs on the login node, and prints the queue / partition snapshot needed to pick a
# partition that does not compete with jobs already in flight. NO sbatch, NO scancel. No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
date "+epoch %s"
R=/data1/home/sunyiq/precip_swap4_gpm_daily_2026_09
S3=/data1/home/sunyiq/precip_swap3_daily_2026_09
A=/data1/home/sunyiq/attr_swap_daily_2026_09
PL=$HOME/hpc_mailbox/inbox/attrswap-daily/payload/pswap4
echo "=== 0. probe: my jobs in flight (all channels), partitions, quota ==="
squeue -u "$USER" -o '%.10i %.30j %.9T %.10M %.9P %R' 2>&1 | head -40
echo "  jobs in flight: $(squeue -u "$USER" -h 2>/dev/null | wc -l)"
squeue -u "$USER" -h -o '%P %T' 2>/dev/null | sort | uniq -c | sed 's/^/  /'
for p in hgpu4 hgpu8 hgpu2p hgpu2; do sinfo -p $p -N -O nodelist,gres:14,gresused:24,statelong:12 2>&1 | sed "s/^/  [$p] /"; done
df -h /data1/home/sunyiq 2>&1 | tail -1 | sed 's/^/  df: /'
echo "=== A. guards ==="
if [ -e "$R" ]; then echo "ABORT: $R already exists"; ls -la "$R" | head; exit 1; fi
[ -d "$PL" ] || { echo "ABORT: payload dir missing: $PL"; exit 1; }
[ -d "$S3/code_1f9804e" ] || { echo "ABORT: Stage-3 archived code missing"; exit 1; }
[ -d "$A/data_shadow/camels_us/camels_attributes_v2.0" ] || { echo "ABORT: attribute dir missing"; exit 1; }
hb=$(sha256sum $A/configs/attrswap_ref27_parity_s900.yml | cut -c1-16)
echo "  base config sha $hb (expect 33bfcc279b213848)"
[ "$hb" = "33bfcc279b213848" ] || { echo "ABORT: base config hash"; exit 1; }
echo "=== B. landing dir + attribute link ==="
mkdir -p $R/logs $R/runs $R/runs_smoke $R/configs $R/hpc_deploy $R/basin_lists $R/data_shadow/camels_us/basin_mean_forcing
ln -s $A/data_shadow/camels_us/camels_attributes_v2.0 $R/data_shadow/camels_us/camels_attributes_v2.0
echo "  attribute files through link: $(ls -L $R/data_shadow/camels_us/camels_attributes_v2.0/ | wc -l)"
echo "=== C. archived code (copied from the Stage-3 landing dir, hash-checked) ==="
cp -r $S3/code_1f9804e $R/code_1f9804e
find $R/code_1f9804e -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null
echo "  files: $(find $R/code_1f9804e -type f | wc -l)"
h=$(sha256sum $R/code_1f9804e/neuralhydrology/datasetzoo/camelsus.py | cut -c1-16)
echo "  camelsus.py sha: $h (expect 51e2e02b382ec103)"
[ "$h" = "51e2e02b382ec103" ] || { echo "ABORT: archived code hash"; exit 1; }
echo "=== D. install scripts, tables, basin lists from the payload ==="
for f in build_shadow4.py build_precip_swap4.py make_pswap4_configs.py pswap4_gate.slurm pswap4_train.slurm cmd_submit4_template.sh; do
  [ -f "$PL/$f" ] || { echo "ABORT: payload file missing: $f"; exit 1; }
  cp "$PL/$f" $R/hpc_deploy/
done
for f in basins_132.txt public_132.txt holdout_132.txt basins_5.txt; do
  [ -f "$PL/basin_lists/$f" ] || { echo "ABORT: basin list missing: $f"; exit 1; }
  cp "$PL/basin_lists/$f" $R/basin_lists/
done
for t in $PL/tables/*; do cp "$t" $R/hpc_deploy/; done
for f in $R/hpc_deploy/* $R/basin_lists/*; do echo "  $(sha256sum $f | cut -c1-16) $(basename $f)"; done
echo "=== E. configs on the login node ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
echo "  CR bytes in slurm/sh/py/txt: $(python -c "import sys; print(sum(open(f,'rb').read().count(bytes([13])) for f in sys.argv[1:]))" $R/hpc_deploy/*.slurm $R/hpc_deploy/*.sh $R/hpc_deploy/*.py $R/basin_lists/*.txt) (expect 0)"
cd $R && python hpc_deploy/make_pswap4_configs.py 2>&1 | tail -2
echo "  configs: $(ls $R/configs/*.yml | wc -l)  arms.txt lines: $(grep -c . $R/configs/arms.txt)"
echo "  manifest sha: $(sha256sum configs/configs_manifest.json | cut -c1-16)"
diff $A/configs/attrswap_ref27_parity_s900.yml $R/configs/pswap4_armG_chirps_s200.yml | sed 's/^/  /'
echo "=== F. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE (no sbatch) ==="
