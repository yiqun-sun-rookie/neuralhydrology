#!/bin/bash
# id23-r-pert seq=3 : redeploy with the missing hydroagent package, resubmit G0.
# Boundaries (prereg 6.2): only ~/id23_r_perturbation and this channel are touched.
# ~/neuralhydrology is read ONLY through a symlink to its CAMELS data; its git is untouched.
# Job names are r_pert_*; NO account-wide scancel is ever issued.
set -o pipefail
DEST=/data1/home/$USER/id23_r_perturbation
SRC=/data1/home/$USER/hpc_mailbox/inbox/id23-r-pert/payload/r_pert_bundle_20260902.tar.gz
EXPECT=c14f971e3626d87212112cdbb261d95e2bccea8d0361333f623c9c7620722ab2

echo "=== BUNDLE CHECK ==="
ls -la "$SRC" 2>&1 | head -2
GOT=$(sha256sum "$SRC" 2>/dev/null | awk '{print $1}')
echo "expect=$EXPECT"
echo "got   =$GOT"
if [ "$GOT" != "$EXPECT" ]; then echo "SHA_MISMATCH_ABORT"; exit 1; fi

echo "=== DEPLOY ==="
rm -rf "$DEST/src" "$DEST/vendor" "$DEST/BUNDLE_MANIFEST.sha256"
mkdir -p "$DEST" /data1/home/$USER/logs/id23_r_perturbation
tar xzf "$SRC" -C "$DEST"
echo "extracted files: $(find "$DEST" -type f | wc -l)"
echo "--- verify manifest ---"
cd "$DEST" && sha256sum -c BUNDLE_MANIFEST.sha256 --quiet 2>&1 | head -5; echo "manifest_rc=$?"

echo "=== CAMELS DATA LINK ==="
mkdir -p "$DEST/data"
[ -e "$DEST/data/camels_us" ] || ln -s /data1/home/$USER/neuralhydrology/data/camels_us "$DEST/data/camels_us"
ls -la "$DEST/data/" | head -4
ls "$DEST/data/camels_us" | head -5

echo "=== ENV SELF-CHECK (light, login node) ==="
source /data1/home/$USER/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
cd "$DEST"
export PYTHONPATH="$DEST/src:$DEST/vendor:$PYTHONPATH"
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1
python - <<'PYCHK'
import sys, numpy, pandas
print("python", sys.version.split()[0], "numpy", numpy.__version__, "pandas", pandas.__version__)
import cma; print("cma", cma.__version__)
from camels_switch_confirmation import run_online_noise_pilot as p
print("RESULTS      ", p.RESULTS, p.RESULTS.exists())
print("PARAMETER_TAB", p.PARAMETER_TABLE.exists())
from camels_switch_confirmation import run_online_noise_real_obs as r
print("G1_CSV       ", r.G1_CSV.exists())
from camels_switch_confirmation.scripts.run_noise_axis_r_perturbation_hpc import admitted_basins, CONTROL_DIR
b = admitted_basins(); print("basins", len(b), "control npz dir exists", CONTROL_DIR.exists())
from camels_switch_confirmation.noise_axis_filtering import ShapePerturbedR, LegacyConstantR
print("R sources OK", LegacyConstantR().observation_variance(0.25,0,float('nan')),
      ShapePerturbedR().observation_variance(0.25,1,100.0))
PYCHK
RC=$?
echo "selfcheck_rc=$RC"
if [ $RC -ne 0 ]; then echo "SELFCHECK_FAILED_NO_SUBMIT"; exit 1; fi

echo "=== SUBMIT G0 (A0 parity gate) ==="
cd "$DEST"
JID=$(sbatch --parsable src/camels_switch_confirmation/hpc/r_pert_a0.slurm 2>&1)
echo "jobid=$JID"
echo "$JID" > "$DEST/LAST_A0_JOBID"

echo "=== WAIT (max ~11 min) ==="
for i in $(seq 1 66); do
    ST=$(squeue -j "$JID" -h -o "%T" 2>/dev/null)
    [ -z "$ST" ] && break
    [ $((i % 6)) -eq 0 ] && echo "t=$((i*10))s state=$ST"
    sleep 10
done

echo "=== RESULT ==="
sacct -j "$JID" -X --format=JobID%10,JobName%12,NodeList%10,State%12,ExitCode%8,Elapsed%10 2>&1 | head -5
echo "--- log tail ---"
tail -25 /data1/home/$USER/logs/id23_r_perturbation/r_pert_a0-${JID}.out 2>&1
echo "--- stderr tail ---"
tail -10 /data1/home/$USER/logs/id23_r_perturbation/r_pert_a0-${JID}.err 2>&1
echo "--- G0 verdict ---"
cat "$DEST/results/23_camels_switch_confirmation/noise_axis_r_perturbation_hpc/a0_summary.json" 2>&1 | head -40
