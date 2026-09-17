#!/bin/bash
# seq=82 stage-3 DEPLOY (PREREG_20260916; user release 2026-09-17 16:48 "go"): cmd_deploy_template3.sh with the four
# assignment lines substituted (PART=hgpu4 WITH_TAU32=1 E4=1 R2="" ; V14 15-year reproduction passed, 0 differing cells). NO sbatch.
# Stage-3 DEPLOY (PREREG_20260916 section 9 'landing dir and channel'; D12 approved 2026-09-16): create the NEW landing
# dir precip_swap3_daily_2026_09, link the shadow data (daymet directly, streamflow / attributes via attr_swap, exactly
# as Stage 2), copy the archived code from the Stage-2 landing dir (hash-checked), install the deploy scripts, tables and
# basin lists from the mailbox payload, generate the configs ON THE LOGIN NODE (POSIX paths), substitute the three
# placeholders in the seven templates with python (never sed-in-place on this file: receipt 56 lesson), and print
# everything needed for section 18. NO sbatch in this command. Sealed landing dirs are only read.
# Placeholders substituted by the same python step: __PART__ (hgpu4|hgpu8), __WITH_TAU32__ (0|1), __E4__ (0|1),
# __R2__ (space-separated Stage-2 window products to retrain, or empty). No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap3_daily_2026_09
S2=/data1/home/sunyiq/precip_swap2_daily_2026_09
A=/data1/home/sunyiq/attr_swap_daily_2026_09
PL=$HOME/hpc_mailbox/inbox/attrswap-daily/payload/pswap3
PART=hgpu4
WITH_TAU32=1
E4=1
R2=""
echo "=== 0. flags ==="
echo "  PART=$PART WITH_TAU32=$WITH_TAU32 E4=$E4 R2='$R2'"
case "$PART" in hgpu4|hgpu8) ;; *) echo "ABORT: PART placeholder not substituted / unknown: $PART"; exit 1;; esac
case "$WITH_TAU32" in 0|1) ;; *) echo "ABORT: WITH_TAU32 placeholder not substituted: $WITH_TAU32"; exit 1;; esac
case "$E4" in 0|1) ;; *) echo "ABORT: E4 placeholder not substituted: $E4"; exit 1;; esac
case "$R2" in "__R2""__") echo "ABORT: R2 placeholder not substituted"; exit 1;; esac   # split literal: survives the whole-file substitution (2026-09-17 fix)
echo "=== A. guard: landing dir must not exist yet; payload present ==="
if [ -e "$R" ]; then echo "ABORT: $R already exists"; ls -la "$R" | head; exit 1; fi
[ -d "$PL" ] || { echo "ABORT: payload dir missing: $PL"; exit 1; }
[ -d "$S2/code_1f9804e" ] || { echo "ABORT: Stage-2 archived code missing"; exit 1; }
echo "=== B. create landing dir + shadow links (same chain as Stage 2) ==="
mkdir -p $R/logs $R/runs $R/runs_smoke $R/configs $R/hpc_deploy $R/basin_lists $R/data_shadow/camels_us/basin_mean_forcing
ln -s /data1/home/sunyiq/neuralhydrology/data/camels_us/basin_mean_forcing/daymet $R/data_shadow/camels_us/basin_mean_forcing/daymet
ln -s $A/data_shadow/camels_us/usgs_streamflow $R/data_shadow/camels_us/usgs_streamflow
ln -s $A/data_shadow/camels_us/camels_attributes_v2.0 $R/data_shadow/camels_us/camels_attributes_v2.0
ls -l $R/data_shadow/camels_us $R/data_shadow/camels_us/basin_mean_forcing | sed 's/^/  /'
dang=$(find -L $R/data_shadow -type l 2>/dev/null)
if [ -n "$dang" ]; then echo "DANGLING: $dang"; exit 1; else echo "  dangling links: none"; fi
nd=$(find -L $R/data_shadow/camels_us/basin_mean_forcing/daymet -name '*_forcing_leap.txt' | wc -l)
echo "  daymet files through link: $nd"
[ "$nd" -eq 677 ] || { echo "ABORT: daymet count $nd"; exit 1; }
echo "  streamflow files through chain: $(find -L $R/data_shadow/camels_us/usgs_streamflow -name '*_streamflow_qc.txt' | wc -l)"
echo "  attribute files: $(ls $R/data_shadow/camels_us/camels_attributes_v2.0/ | wc -l)"
echo "=== C. archived code (copied from the Stage-2 landing dir, hash-checked) ==="
cp -r $S2/code_1f9804e $R/code_1f9804e
echo "  files: $(find $R/code_1f9804e -type f -not -name '*.pyc' | wc -l)"
h=$(sha256sum $R/code_1f9804e/neuralhydrology/datasetzoo/camelsus.py | cut -c1-16)
echo "  camelsus.py sha: $h (expect 51e2e02b382ec103)"
[ "$h" = "51e2e02b382ec103" ] || { echo "ABORT: archived code hash"; exit 1; }
echo "=== D. install scripts, tables, basin lists ==="
for f in build_precip_swap3.py make_pswap3_configs.py guard_T16.py e4_copy_runs.py p7_hydro_year.py v9_streamflow.py scripts_public_median.py pswap3_gate_ref.slurm pswap3_gate_product.slurm pswap3_train.slurm pswap3_train_ep60.slurm pswap3_guard_T16.slurm pswap3_eval_ckpt.slurm pswap3_p7.slurm; do
  [ -f "$PL/$f" ] || { echo "ABORT: payload file missing: $f"; exit 1; }
  cp "$PL/$f" $R/hpc_deploy/
done
for f in basins_529.txt holdout_107.txt basins_5.txt caravan_timezone_529.csv fixed_std_offset_529.csv; do
  [ -f "$PL/basin_lists/$f" ] || { echo "ABORT: basin list missing: $f"; exit 1; }
  cp "$PL/basin_lists/$f" $R/basin_lists/
done
for t in $PL/tables/*_daily_529.csv.gz; do cp "$t" $R/hpc_deploy/; done
for f in $R/hpc_deploy/* $R/basin_lists/*; do echo "  $(sha256sum $f | cut -c1-16) $(basename $f)"; done
echo "  fixed_std_offset_529.csv CR bytes: $(python -c "import sys; print(open(sys.argv[1],'rb').read().count(bytes([13])))" $R/basin_lists/fixed_std_offset_529.csv) (expect 0)"
echo "=== E. substitute placeholders in the seven templates (python, not sed) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
cd $R && python - "$PART" "$WITH_TAU32" "$E4" "$R2" <<'PYEOF'
import sys, pathlib
part, tau, e4, r2 = sys.argv[1:5]
subs = {'__PART__': part, '__WITH_TAU32__': tau, '__E4__': e4, '__R2__': r2}
files = ['pswap3_gate_ref.slurm', 'pswap3_gate_product.slurm', 'pswap3_train.slurm', 'pswap3_train_ep60.slurm',
         'pswap3_guard_T16.slurm', 'pswap3_eval_ckpt.slurm', 'pswap3_p7.slurm', 'cmd_submit3.sh']
src_submit = pathlib.Path.home() / 'hpc_mailbox' / 'inbox' / 'attrswap-daily' / 'payload' / 'pswap3' / 'cmd_submit_template3.sh'
pathlib.Path('hpc_deploy/cmd_submit3.sh').write_text(src_submit.read_text(), newline=chr(10))
for f in files:
    p = pathlib.Path('hpc_deploy') / f
    t = p.read_text()
    for k, v in subs.items():
        t = t.replace(k, v)
    left = [k for k in subs if k in t]
    assert not left, (f, left)
    p.write_text(t, newline=chr(10))
    print('  substituted', f)
PYEOF
grep -H '^#SBATCH -p' hpc_deploy/*.slurm | sed 's/^/  /'
grep -HnE '^(PART|WITH_TAU32|E4|R2)=' hpc_deploy/cmd_submit3.sh | sed 's/^/  /'
echo "=== F. generate configs on the login node (POSIX paths) ==="
opts=""; [ "$WITH_TAU32" = "1" ] && opts="$opts --with-tau32"; [ -n "$R2" ] && opts="$opts --with-r2"
python hpc_deploy/make_pswap3_configs.py $opts 2>&1 | tail -3
echo "  configs: $(ls $R/configs/*.yml | wc -l)"
echo "  manifest base_sha16: $(python -c "import json; print(json.load(open('configs/configs_manifest.json'))['base_sha16'])")"
sha256sum configs/configs_manifest.json | cut -c1-16
echo "  --- diff base vs pswap3_ep60_ref_daymet_s100 (allowed keys only) ---"
diff $A/configs/attrswap_ref27_parity_s900.yml $R/configs/pswap3_ep60_ref_daymet_s100.yml | sed 's/^/  /'
echo "=== G. partitions right now ==="
sinfo -p hgpu4,hgpu8 -o '%P %.6D %.10T %.20G %.30N' 2>&1 | sed 's/^/  /'
echo "=== H. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE (no sbatch) ==="
