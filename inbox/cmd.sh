#!/bin/bash
# seq=14  build ~/adv531, verify data identity against the local fingerprints,
#         then run the smoke test. The job is only submitted if the data matches.
set -o pipefail
export LC_ALL=C
SRC=/data1/home/$USER/neuralhydrology
DST=/data1/home/$USER/adv531
MB=/data1/home/$USER/hpc_mailbox

echo "=== 0. PAYLOAD ==="
ls -l $MB/payload/adv531.tar.gz 2>&1 | awk '{print $5, $9}'
echo "md5=$(md5sum $MB/payload/adv531.tar.gz 2>/dev/null | cut -c1-32)  expect=b74a31e1899dd9c1e59d8ea86768aba8"

echo "=== 1. DATA: copy maurer first (stale), payload overwrites the 4 repaired files after ==="
mkdir -p $DST/data/camels_us/basin_mean_forcing
if [ ! -d $DST/data/camels_us/basin_mean_forcing/maurer ]; then
  cp -r $SRC/data/camels_us/basin_mean_forcing/maurer $DST/data/camels_us/basin_mean_forcing/maurer
fi
echo "maurer files: $(find $DST/data/camels_us/basin_mean_forcing/maurer -type f | wc -l)"
ln -sfn $SRC/data/camels_us/usgs_streamflow        $DST/data/camels_us/usgs_streamflow
ln -sfn $SRC/data/camels_us/camels_attributes_v2.0 $DST/data/camels_us/camels_attributes_v2.0

echo "=== 2. UNPACK CODE + MODEL + THE 4 REPAIRED FORCING FILES ==="
tar xzf $MB/payload/adv531.tar.gz -C $DST || { echo "UNPACK_FAILED"; exit 1; }
echo "top level: $(ls $DST | tr '\n' ' ')"

echo "=== 3. REPAIRED HEADERS (must be tab-separated Maurer style) ==="
for p in 03/02108000 09/05120500 11/07067000 15/09492400; do
  printf "  %s: " "$p"
  sed -n '4p' $DST/data/camels_us/basin_mean_forcing/maurer/${p}_lump_maurer_forcing_leap.txt | cut -c1-42
done

echo "=== 4. DATA FINGERPRINTS vs LOCAL ==="
cd $DST
OK_DATA=1
check () {  # $1=dir $2=expected
  h=$(find -L "$1" -type f | sort | xargs md5sum 2>/dev/null | awk '{print $1}' | md5sum | cut -c1-32)
  n=$(find -L "$1" -type f | wc -l)
  if [ "$h" = "$2" ]; then echo "  MATCH  $1  files=$n"; else echo "  DIFFER $1  files=$n got=$h want=$2"; OK_DATA=0; fi
}
check data/camels_us/basin_mean_forcing/maurer   484c980b8235db03171b3b96788d8a1b
check data/camels_us/usgs_streamflow             796f63d789251cef6d7548276849b421
check data/camels_us/camels_attributes_v2.0      a1ea6856c15ddf50be3a03dbb7569321

echo "=== 5. CONFIG PATH SEPARATOR ==="
C=$DST/results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/config.yml
sed -i 's|^data_dir: data\\camels_us|data_dir: data/camels_us|' $C
grep -E "^data_dir|^dataset" $C | sed 's/^/  /'

echo "=== 6. CRLF SCRUB + STAGE ==="
find $DST/src $DST/neuralhydrology -name "*.py" -exec sed -i 's/\r$//' {} \; 2>/dev/null
mkdir -p $DST/reference $DST/logs $MB/outbox
cp -f $MB/inbox/smoke_reference.json $DST/reference/smoke_reference.json
cp -f $MB/inbox/adv531_smoke.slurm  $DST/adv531_smoke.slurm
sed -i 's/\r$//' $DST/adv531_smoke.slurm

echo "=== 7. ENV CHECK (direct interpreter, no activate) ==="
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python
$P -c "import sys, torch, numpy, pandas; print('  python', sys.version.split()[0], '| torch', torch.__version__, '| numpy', numpy.__version__, '| pandas', pandas.__version__)" 2>&1 | tail -2
cd $DST && $P -c "
import sys; sys.path.insert(0,'.')
from src.adversarial.model_wrapper import CudaLSTMWrapper
from src.adversarial.data_loader import load_basin_data
print('  attack-chain imports OK')
" 2>&1 | tail -3

echo "=== 8. SUBMIT SMOKE (only if data matched) ==="
if [ "$OK_DATA" != "1" ]; then echo "  DATA MISMATCH -> NOT SUBMITTING"; exit 0; fi
cd $DST
JID=$(sbatch --parsable adv531_smoke.slurm 2>&1)
echo "  jobid=$JID"

echo "=== 9. WAIT (max 12 min) ==="
for i in $(seq 1 72); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && break
  [ $((i % 6)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done

echo "=== 10. RESULT ==="
sacct -j "$JID" -X --format=JobID%10,JobName%14,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1
echo "--- stdout ---"
cat $MB/outbox/slurm_${JID}.out 2>/dev/null | tail -45
echo "--- stderr (tail) ---"
cat $MB/outbox/slurm_${JID}.err 2>/dev/null | tail -10
rm -f $MB/outbox/slurm_*.out $MB/outbox/slurm_*.err
