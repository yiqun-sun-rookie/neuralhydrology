#!/bin/bash
set -o pipefail
# Create the read-only shared install /data1/home/sunyiq/openhydronet_shared from this task's own landing dir, verify it, and run one GPU smoke job through the template.
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
SH=/data1/home/sunyiq/openhydronet_shared
P6="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v6"
date --iso-8601=seconds
for f in env.sh run_template.slurm VERSION README.md; do [ -f "$P6/$f" ] || { echo "MISSING payload $f"; exit 1; }; done
if [ -e "$SH" ]; then echo "EXISTS $SH - not overwriting"; ls -la "$SH" | head; exit 0; fi
mkdir -p "$SH" || exit 1
cp -a "$ROOT/pysite" "$SH/pysite" && cp -a "$ROOT/src/flood-forecasting" "$SH/flood-forecasting" || { echo "COPY_FAILED"; exit 1; }
cp "$P6/env.sh" "$P6/run_template.slurm" "$P6/VERSION" "$P6/README.md" "$SH/"
sed -i 's/\r$//' "$SH/env.sh" "$SH/run_template.slurm" "$SH/VERSION" "$SH/README.md"
find "$SH/pysite" "$SH/flood-forecasting" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null
chmod -R a-w "$SH"
du -sh "$SH"; ls -la "$SH"
echo "=== identical to the verified install? ==="
( cd "$ROOT/src/flood-forecasting" && git rev-parse HEAD && git status --porcelain | wc -l )
diff -rq "$ROOT/pysite" "$SH/pysite" -x __pycache__ | head -3; echo "pysite diff rc=$?"
echo "=== import test in a fresh shell from the shared location ==="
bash -c 'source /data1/home/sunyiq/openhydronet_shared/env.sh && cd /tmp && python -c "
import itertools, googlehydrology, zarr
from googlehydrology.modelzoo import get_model
print(\"googlehydrology\", googlehydrology.__file__, \"| batched\", hasattr(itertools, \"batched\"), \"| zarr\", zarr.__version__)
" && type ohn | head -2'
echo "=== smoke job through the template ==="
T="$ROOT/shared_smoke.slurm"
sed -e "s#^\#SBATCH --job-name=.*#\#SBATCH --job-name=ohn_shared_smoke#" -e "s#^\#SBATCH -p .*#\#SBATCH -p hgpu8#" -e "s#^\#SBATCH -t .*#\#SBATCH -t 00:30:00#" \
    -e "s#PROJECT_ROOT_CHANGEME#$ROOT#g" -e "s#CONFIG_FILE_CHANGEME#$ROOT/configs/smoke.yml#" -e "s#EXPERIMENT_NAME_CHANGEME#smoke#" -e "s#RUN_PARENT_CHANGEME#$ROOT/runs#" "$SH/run_template.slurm" > "$T"
grep -nE 'CHANGEME' "$T" | head -3
grep -nE '^#SBATCH|^PROJECT_ROOT|^CONFIG|^EXPERIMENT|^RUN_PARENT' "$T" | cut -c1-140
if squeue -u sunyiq -h -o '%j' | grep -qx ohn_shared_smoke; then echo "already queued"; exit 0; fi
out=$(sbatch "$T" 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$JID" ] && echo "jobid=$JID" || echo "SUBMIT_FAILED"
exit 0
