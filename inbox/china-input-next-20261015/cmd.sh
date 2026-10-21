#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 60s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'FIXED_PATHS'
import os,json,base64,zlib,hashlib,datetime,time
from pathlib import Path
START=time.monotonic();BASE=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001');FIXED={'depth': '/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/numerical_v1/depth_original.tif', 'mask': '/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/numerical_v1/mask_original.tif', 'geometry': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/preflight_v1/geometry_all.geojson', 'topography': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/preflight_v1/topography.txt', 'scope': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/preflight_v1/scope.csv', 'dem': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/source_handoff_resume_v1/extract/dem/wc2.1_30s_elev.tif', 'glim': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_raster_materials_20261020_v1/processed_glim.tif', 'permeability': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_raster_materials_20261020_v1/processed_permeability.tif', 'porosity': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_raster_materials_20261020_v1/processed_porosity.tif'};PROBES=['/data1/home/sunyiq/china_input_completion_hpc_20261015_001/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/preflight_v1/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/preflight_v1/inputs/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/common_source_bytes_v1/geometry/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/common_source_bytes_v1/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/common_source_restoration_20261019_v1/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/common_source_restoration_20261019_v1/geometry/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/common_source_transport_20261020_v1/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/source_handoff_resume_v1/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/source_handoff_resume_v1/extract/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geometry/0_catchment_boundary.zip', '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/inputs_ccam_original/0_catchment_boundary.zip']
result=dict(kind='GAP27888_PATH_INVENTORY',revision='fixed_paths_v2',base=str(BASE),
    scope='12 fixed archive paths only, not a whole-machine absence claim',max_depth=0,max_entries=200,
    source_content_reads=0,source_decoding=0,source_writes=0,new_jobs=0,downloads=0,model_calls=0,
    automatic_checks_enabled=False,expected_archive_bytes=18108565,
    expected_archive_sha256='8197e332342eb83b536863e340aabbe3a23e90752522438ee25ef1f4ba584aee',
    archive_candidates=[],archive_probes=[],fixed={},root_context=[],root_context_truncated=False,errors=[],complete=False)
def stat_one(value):
    p=Path(value)
    try:
        assert not p.is_symlink() and p.resolve(strict=True)==p,'Symlink or resolved path conflict'
        s=p.stat();return dict(path=value,exists=True,is_file=p.is_file(),bytes=s.st_size,mtime_ns=s.st_mtime_ns)
    except Exception as e:return dict(path=value,exists=False,error_type=type(e).__name__,message=str(e)[:500])
assert BASE.resolve(strict=True)==BASE and len(PROBES)==12 and len(FIXED)==9
for value in PROBES:
    row=stat_one(value);result['archive_probes'].append(row)
    if row['exists']:
        result['archive_candidates'].append(row)
        if not row['is_file'] or row['bytes']!=18108565:result['errors'].append(dict(path=value,error='Archive identity unresolved'))
    elif row['error_type']!='FileNotFoundError':result['errors'].append(row)
for name,value in FIXED.items():result['fixed'][name]=stat_one(value)
try:
    with os.scandir(BASE) as it:
        for index,entry in enumerate(it):
            if index==200:result['root_context_truncated']=True;break
            result['root_context'].append(dict(name=entry.name,is_dir=entry.is_dir(follow_symlinks=False),is_symlink=entry.is_symlink()))
except Exception as e:result['root_context_error']=dict(type=type(e).__name__,message=str(e)[:500])
result.update(complete=not result['errors'],seconds=time.monotonic()-START,
    server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
raw=(json.dumps(result,ensure_ascii=False,allow_nan=False,separators=(',',':'))+'\n').encode();assert len(raw)<1048576
print('GEOLOGY_RECOVERY_BYTES='+str(len(raw)));print('GEOLOGY_RECOVERY_SHA256='+hashlib.sha256(raw).hexdigest())
print('GEOLOGY_RECOVERY_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode());print('GEOLOGY_RECOVERY_DONE')

FIXED_PATHS
