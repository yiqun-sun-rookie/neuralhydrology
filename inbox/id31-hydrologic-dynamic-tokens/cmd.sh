#!/usr/bin/env bash
# ID31 seq=69 : full run manifest, token-count diagnostics search, and arm inventory.
set -o pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
INV="$ROOT/results/31_hydrologic_dynamic_tokens/_invocations/id31_DL01_s100_slurm216549"
DL01="$ROOT/results/31_hydrologic_dynamic_tokens/DL01/hydrologic_dynamic_tokens_DL01_learned_end_to_end_s100_2026_0831_1223_ep30"
RES="$ROOT/results/31_hydrologic_dynamic_tokens"

echo "=== A. FULL RUN MANIFEST (all keys, values truncated) ==="
python - "$INV/run_manifest.json" <<'PY' 2>&1 || true
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
v = json.loads(p.read_text(encoding="utf-8"))
def show(o, k=""):
    s = json.dumps(o, sort_keys=True) if not isinstance(o, str) else o
    if len(s) > 700: s = s[:700] + " ...TRUNCATED(len=%d)" % len(s)
    print("  %-34s %s" % (k, s))
for k in sorted(v):
    show(v[k], k)
PY

echo "=== B. METRICS ARTIFACT ==="
python - "$INV/run_manifest.json" <<'PY' 2>&1 || true
import json, sys
from pathlib import Path
v = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print("metrics_artifact_path:", v.get("metrics_artifact_path"))
print("metrics_artifact_sha256:", v.get("metrics_artifact_sha256"))
PY
ART=$(python -c "import json;print(json.load(open('$INV/run_manifest.json')).get('metrics_artifact_path') or '')" 2>/dev/null)
if test -n "$ART" && test -f "$ROOT/$ART"; then
  echo "-- artifact head --"; head -c 2500 "$ROOT/$ART" 2>&1 || true; echo
  sha256sum "$ROOT/$ART" 2>&1 || true
else
  echo "ARTIFACT_NOT_FOUND [$ART]"
fi

echo "=== C. TOKEN DIAGNOSTICS IN TRAINING LOG ==="
grep -n -i -E 'token_duration|mean_token|max_token|token_count|boundary|n_token|duration' "$DL01/output.log" 2>&1 | grep -v 'avg_dynamic_token_count' | head -25 || echo "NO_TOKEN_DIAGNOSTIC_LINES"
echo "-- distinct metric key names seen in epoch lines --"
grep -o -E '[a-z_]+:' "$DL01/output.log" 2>/dev/null | sort | uniq -c | sort -rn | head -20 || true

echo "=== D. WHAT IS IN THE EPOCH-30 VALIDATION DIR ==="
ls -la "$DL01/validation/model_epoch030/" 2>&1 || true

echo "=== E. ARM INVENTORY (which arms actually have runs) ==="
for arm in DT00 DT04 DT08 DT16 DR01 DL00 DL01; do
  if test -d "$RES/$arm"; then
    n=$(find "$RES/$arm" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    echo "$arm : dir_exists run_subdirs=$n"
    find "$RES/$arm" -maxdepth 1 -mindepth 1 -type d -printf '    %f\n' 2>/dev/null | head -5 || true
  else
    echo "$arm : NO_DIR"
  fi
done
echo "-- invocation records --"
find "$RES/_invocations" -maxdepth 1 -mindepth 1 -type d -printf '  %f\n' 2>/dev/null | sort || true

echo "=== F. EPOCH-30 CHECKPOINT PRESENT FOR RESTART-FREE INFERENCE ==="
ls -la "$DL01"/model_epoch0[123]0.pt 2>&1 || true

echo "ID31_SEQ69_COMPLETE"
