#!/bin/bash
# a02 seq=8 : restore the three python files I mangled with sed, re-verify, rerun smoke.
# Root cause: seq=6 ran `sed -i 's/\r$//'` over scripts/*.py and src/**/*.py as well
# as the slurm files. Iron rule 4 only concerns shell/slurm scripts; python handles
# CRLF fine. The sed changed their bytes, so GATE 2 (sha256) correctly failed.
export LC_ALL=C
HOME_DIR=/data1/home/$USER
PKG=$HOME_DIR/nature_1st_a02

echo "=== A RESTORE ORIGINALS FROM TARBALL ==="
cd $HOME_DIR || exit 1
tar xzf nature_1st_a02.tar.gz \
    nature_1st_a02/scripts/train_depth_v1.py \
    nature_1st_a02/src/stage_dataset_v2.py \
    nature_1st_a02/src/models/simple_lstm_v2.py 2>&1 | tail -2
echo "  restored 3 files"
for f in scripts/train_depth_v1.py src/stage_dataset_v2.py src/models/simple_lstm_v2.py; do
  printf "  %-34s %s\n" "$f" "$(sha256sum $PKG/$f | cut -c1-16)"
done

echo "=== B CONFIRM SLURM FILES STILL LF (they must stay converted) ==="
file $PKG/hpc/a02_smoke.slurm $PKG/hpc/a02_preceding_s42.slurm 2>&1 | sed 's/^/  /'

echo "=== C RE-RUN PACKAGE VERIFICATION ==="
cd $PKG
/data1/home/$USER/miniconda3/envs/nh_final/bin/python hpc/verify_package.py 2>&1 | tail -8
VERIFY_RC=${PIPESTATUS[0]}
if [ "$VERIFY_RC" != "0" ]; then
  echo "  verification still failing -- not resubmitting"
  exit 0
fi

echo "=== D RESUBMIT SMOKE ==="
cd $PKG/hpc
JID=$(sbatch --parsable a02_smoke.slurm 2>&1)
echo "  jobid=$JID"

echo "=== E WAIT (max 55 min) ==="
for i in $(seq 1 330); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && { echo "  finished at t=$((i*10))s"; break; }
  [ $((i % 12)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done

echo "=== F ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%10,JobName%12,NodeList%10,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== G STDOUT (tail 70) ==="
tail -70 $PKG/logs/a02_smoke-${JID}.out 2>&1

echo "=== H STDERR (tail 15) ==="
tail -15 $PKG/logs/a02_smoke-${JID}.err 2>&1
