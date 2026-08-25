#!/bin/bash
set -o pipefail
echo "=== TIME ==="; date --iso-8601=seconds
echo "=== RELONG (the four resubmitted) ==="
sacct -X -n -P -j 211001 --format=JobID,State,Elapsed,Timelimit,NodeList 2>/dev/null || echo 'no record yet'
echo "=== QUEUE ==="
squeue -u sunyiq -h -o '%.12i %.14j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22|relong' || echo none
echo "=== END ==="; date --iso-8601=seconds
exit 0
