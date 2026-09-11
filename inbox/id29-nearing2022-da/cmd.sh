set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== 219423 / warmpair state ==="
sacct -X -n -P -S 2026-09-01 --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22-warm' || echo '  none'
echo "=== pair dirs ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for S in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$S" ] && echo "  PRESENT $S" || echo "  MISSING $S"; done
echo "=== script line 94 + git state ==="
sed -n '90,96p' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" || true
cd "$ROOT" && git log -1 --format='%h %ci %s' 2>/dev/null || true
git status --short -- src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py 2>/dev/null || true
echo "=== gate artifact ==="
P="$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
[ -f "$P" ] && python3 -c "import json;d=json.load(open('$P'));print(d.get('released_code_numerical_status'))" 2>/dev/null || echo MISSING
exit 0
