#!/bin/bash
set -o pipefail
echo "=== A ALL GPU PARTITIONS (real node state, not squeue) ==="
sinfo -o "%.10P %.6a %.6D %.8t %.32N" -p hgpu2p,hgpu2,hgpu4,hgpu8 2>&1

echo "=== B IDLE NODES ONLY ==="
sinfo -h -o "%P %t %N" -p hgpu2p,hgpu2,hgpu4,hgpu8 2>&1 | grep -E ' (idle|mix) ' || echo "  none idle or mix"

echo "=== C DOWN REASONS ==="
sinfo -R -h 2>&1 | head -8 || true

echo "=== D MY QUEUE ==="
squeue -u "$USER" -o "%.10i %.12j %.10P %.10T %.10M %.20S %.20r" 2>&1 | head -12
echo "=== END ==="
