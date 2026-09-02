#!/bin/bash
# Delete the stray seq=111 export copies. Guarded: refuses any other path.
set -o pipefail
STRAY="$HOME/hpc_mailbox/outbox/zhenjiang-oyv-n4/n4_impact_export_20260901"
CANON=/data1/home/sunyiq/zhenjiang_oyv_v1

case "$STRAY" in
  */hpc_mailbox/outbox/zhenjiang-oyv-n4/n4_impact_export_20260901) ;;
  *) echo "REFUSED: unexpected path $STRAY"; exit 2 ;;
esac

echo "=== inventory before delete ==="
[ -d "$STRAY" ] && du -sh "$STRAY" && find "$STRAY" -type f | sort || echo "already absent"

echo "=== deleting ==="
rm -rf "$STRAY"

echo "=== verify ==="
[ -d "$STRAY" ] && { echo "FAIL: still present"; exit 1; } || echo "OK: removed"
echo "--- canonical results MUST be intact ---"
ls -la "$CANON"/ladder_impact "$CANON"/n4_impact 2>/dev/null | head -40
echo "=== DONE ==="
