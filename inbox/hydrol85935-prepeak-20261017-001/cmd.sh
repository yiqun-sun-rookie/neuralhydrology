#!/bin/bash
# seq2: deploy frozen bundle, verify code and input data, submit ONE smoke job (1 basin, 3 limits).
set -o pipefail
CH=hydrol85935-prepeak-20261017-001
ROOT=/data1/home/sunyiq/hydrol85935_prepeak_small_bounds_20261017_001
DATA=/data1/home/sunyiq/neuralhydrology/data/camels_us
PAY=$HOME/hpc_mailbox/inbox/$CH/payload/prepeak_bundle_v1.tar.gz
echo "=== PAYLOAD ==="
echo "c41066b1ec0e3f4e6f84f1a10a6f3c4d0ac614d8cec0f367902af82a86561a7e  $PAY" | sha256sum -c - || { echo PAYLOAD_MISMATCH; exit 2; }
if [ -e "$ROOT/bundle" ]; then echo "BUNDLE_ALREADY_DEPLOYED (no overwrite)"; exit 4; fi
mkdir -p "$ROOT/logs" "$ROOT/control" || exit 1
tar -xzf "$PAY" -C "$ROOT" || { echo EXTRACT_FAILED; exit 1; }
echo "=== MANIFEST ==="
cd "$ROOT/bundle" || exit 1
python3 - <<'PY' || { echo MANIFEST_FAILED; exit 2; }
import hashlib, json, sys
m = json.load(open('MANIFEST.json'))
bad = [k for k, v in m.items() if not k.startswith('_') and hashlib.sha256(open(k, 'rb').read()).hexdigest() != v]
print('files', len([k for k in m if not k.startswith('_')]), 'bad', bad)
sys.exit(1 if bad else 0)
PY
echo "=== DATA IDENTITY ==="
cat > "$ROOT/control/data_checks.sha256" <<CHK
b950202d89762059bde1cc4d7dcb923e9ea56d8f9e33373734462bb1bcb8d071  $DATA/basin_mean_forcing/maurer/01/01022500_lump_maurer_forcing_leap.txt
46ac37932d4b4c9a119d0577bfa6887ead379709f09f384996b808f0aff7cc68  $DATA/usgs_streamflow/01/01022500_streamflow_qc.txt
ddc79c8771f36885ed54e1a53696237d6cd8510e654f03d5787381213cb7c639  $DATA/basin_mean_forcing/maurer/07/05495000_lump_maurer_forcing_leap.txt
178c09eb14152af9e34e21d6d2f443b3ef1a9366101a9fde526bfb7a17478a2a  $DATA/usgs_streamflow/07/05495000_streamflow_qc.txt
eb5baeaa1d9eb2c0a96de028b31e3727e05c677dda52270d32e9349b3d908426  $DATA/basin_mean_forcing/maurer/17/14400000_lump_maurer_forcing_leap.txt
deffe37ee6a80cefdfaff8b9be088fedf9ab96dc133bd6aad345643b41f0d89a  $DATA/usgs_streamflow/17/14400000_streamflow_qc.txt
6a3a80256afbaea13f59f279c174d3c010156b826ffb53a4cfb5508814404f5f  $DATA/camels_attributes_v2.0/camels_clim.txt
2ffe3871541b93bde02f72df6c34933cb91edb45af363fd7d50c3eaa7da0b5e6  $DATA/camels_attributes_v2.0/camels_geol.txt
7dcae3ea8c28e6485fc9e39b3c5e8bb509d6354ebe9b0b98873ec47fa36e3c41  $DATA/camels_attributes_v2.0/camels_hydro.txt
f3a85272cd934c6e12386db5f21979675fc891844250a335135786ad9a2de445  $DATA/camels_attributes_v2.0/camels_name.txt
2acabec448fda2d7d93c2182a8a148e0f6a2dfc40f6f0944ec09eda6eeea0a6d  $DATA/camels_attributes_v2.0/camels_soil.txt
b64ca9923bcaccf21dde33137903797919e8d6732edd7849f8534e0ddcbec8e8  $DATA/camels_attributes_v2.0/camels_topo.txt
ea97f5d91a2f5acccef21df08417729aade51afe9a2651ab30c2990e7ad63d74  $DATA/camels_attributes_v2.0/camels_vege.txt
CHK
sha256sum -c "$ROOT/control/data_checks.sha256" || { echo DATA_MISMATCH_NOT_SUBMITTED; exit 3; }
echo "=== MODEL VS PARENT COPY (info) ==="
sha256sum "$ROOT/bundle/repo/results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/model_epoch030.pt" /data1/home/sunyiq/hydrol85935_revision_20261008_001/original_models/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/model_epoch030.pt 2>&1
echo "=== SUBMIT SMOKE ==="
cd "$ROOT/bundle" || exit 1
out=$(sbatch --export=ALL,STRIDE=1,LIMIT=1,OUTNAME=smoke prepeak.sbatch 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$JID" ] || { echo SUBMIT_FAILED; exit 1; }
echo "smoke_jobid=$JID"
echo "$JID" > "$ROOT/control/smoke_jobid.txt"
sleep 5
squeue -j "$JID" -h -o '%i %P %T %R %S' 2>&1
