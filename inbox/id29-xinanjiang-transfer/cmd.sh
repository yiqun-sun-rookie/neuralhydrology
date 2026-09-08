#!/bin/bash
# Read-only comparison of the two failed basins' shared inputs against frozen hashes.
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json,pathlib
root=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
data=pathlib.Path('/data1/home/sunyiq/neuralhydrology/data/camels_us')
expected=json.loads((root/'bundle/inputs/raw_input_hashes.json').read_text())
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for basin in ['05120500','09492400']:
    paths=[]
    paths += sorted((data/'basin_mean_forcing/maurer').glob('*/'+basin+'_lump_maurer_forcing_leap.txt'))
    paths += sorted((data/'usgs_streamflow').glob('*/'+basin+'_streamflow_qc.txt'))
    paths += [data/'camels_attributes_v2.0/camels_topo.txt']
    print('BASIN',basin,'FOUND',len(paths))
    for path in paths:
        rel=path.relative_to(data).as_posix()
        stat=path.stat()
        actual=digest(path)
        print(json.dumps({'relative_path':rel,'expected_sha256':expected.get(rel),'actual_sha256':actual,
                          'match':expected.get(rel)==actual,'bytes':stat.st_size,
                          'mtime_ns':stat.st_mtime_ns},sort_keys=True))
PY
