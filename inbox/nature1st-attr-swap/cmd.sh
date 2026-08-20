#!/bin/bash
# nature1st-attr-swap seq=13 -- prove the two arms shared model + data split.
# READ ONLY. No sbatch anywhere.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
A=$RUN/models/q_lstm_control_hpc_s42
B=$RUN/models/q_lstm_hydroatlas_hpc_s42

echo "=== A. SPLIT FINGERPRINT (decisive: same file, same bytes?) ==="
for d in "$A" "$B"; do
    echo "--- $(basename $d) ---"
    python -c "
import json,sys
m=json.load(open('$d/model_info.json'))
print('splits_path   ', m.get('splits_path'))
print('splits_sha256 ', m.get('splits_sha256'))
print('n_train_stations', m.get('n_train_stations'), ' n_train_samples', m.get('n_train_samples'))
print('seed', m.get('seed'), ' model_class', m.get('model_class'), ' n_params', m.get('n_model_params'))
print('channels', len(m.get('channels',[])), m.get('channels'))
" 2>&1
done

echo "=== B. FULL CONFIG DIFF (only the attribute source should differ) ==="
python - <<'PY' 2>&1
import json
a=json.load(open('/data1/home/sunyiq/nature_1st/models/q_lstm_control_hpc_s42/config.json'))
b=json.load(open('/data1/home/sunyiq/nature_1st/models/q_lstm_hydroatlas_hpc_s42/config.json'))
keys=sorted(set(a)|set(b))
same=[]; diff=[]
for k in keys:
    (same if a.get(k)==b.get(k) else diff).append(k)
print("IDENTICAL in both runs (%d keys):" % len(same))
print("  " + ", ".join(same))
print()
print("DIFFERENT (%d keys):" % len(diff))
for k in diff:
    print(f"  {k}: control={a.get(k)!r}  treatment={b.get(k)!r}")
PY

echo "=== C. EVAL UNIVERSE (same 431 stations scored?) ==="
python - <<'PY' 2>&1
import json, hashlib, pandas as pd
for tag,d in [("control","q_lstm_control_hpc_s42"),("treatment","q_lstm_hydroatlas_hpc_s42")]:
    p=f"/data1/home/sunyiq/nature_1st/models/{d}"
    ev=json.load(open(f"{p}/eval_val.json"))
    cs=pd.read_csv(f"{p}/eval_val_per_station.csv")
    ids=",".join(map(str,sorted(cs.station.tolist())))
    print(f"{tag:<10} n_eval={ev['n_stations_eval']} n_scored={ev['n_stations_scored']} "
          f"station_list_sha256={hashlib.sha256(ids.encode()).hexdigest()[:16]}")
PY

echo "=== D. NORMALISATION STATS: meteorology identical? ==="
python - <<'PY' 2>&1
import json, hashlib
for tag,d in [("control","q_lstm_control_hpc_s42"),("treatment","q_lstm_hydroatlas_hpc_s42")]:
    n=json.load(open(f"/data1/home/sunyiq/nature_1st/models/{d}/norm_stats.json"))
    for key in ("met_norm","q_norm","daily_met_norm"):
        if key in n:
            h=hashlib.sha256(json.dumps(n[key],sort_keys=True).encode()).hexdigest()[:16]
            print(f"{tag:<10} {key:<15} {h}")
PY
echo "=== END seq=13 ==="
