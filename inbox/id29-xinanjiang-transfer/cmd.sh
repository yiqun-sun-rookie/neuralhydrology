#!/bin/bash
# Read-only check whether mismatches are confined to skipped forcing headers.
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json,pathlib
data=pathlib.Path('/data1/home/sunyiq/neuralhydrology/data/camels_us')
for basin,subdir in [('05120500','09'),('09492400','15')]:
    path=data/'basin_mean_forcing/maurer'/subdir/(basin+'_lump_maurer_forcing_leap.txt')
    raw=path.read_bytes(); lines=raw.splitlines(keepends=True)
    print(json.dumps({'basin_id':basin,'header':[v.decode(errors='replace').rstrip('\r\n') for v in lines[:4]],
                      'body_sha256':hashlib.sha256(b''.join(lines[4:])).hexdigest(),
                      'line_count':len(raw.splitlines()),'bytes':len(raw)},sort_keys=True))
PY
