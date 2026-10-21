#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 60s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PATH_INVENTORY'
import os,json,base64,zlib,hashlib,datetime,time
from pathlib import Path
START=time.monotonic()
BASE=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001')
FIXED={'depth': '/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/numerical_v1/depth_original.tif', 'mask': '/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/numerical_v1/mask_original.tif', 'geometry': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/preflight_v1/geometry_all.geojson', 'topography': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/preflight_v1/topography.txt', 'scope': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/preflight_v1/scope.csv', 'dem': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/source_handoff_resume_v1/extract/dem/wc2.1_30s_elev.tif', 'glim': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_raster_materials_20261020_v1/processed_glim.tif', 'permeability': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_raster_materials_20261020_v1/processed_permeability.tif', 'porosity': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_raster_materials_20261020_v1/processed_porosity.tif', 'preselected_geometry': '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/common_source_bytes_v1/geometry/preselected_boundaries.geojson'}
result=dict(kind='GAP27888_PATH_INVENTORY',base=str(BASE),max_depth=2,max_entries=5000,
    excluded_directory_names=['main','independent','members','logs','private_git','objects','deps','deps_v2','predictions'],
    original_archive_name='0_catchment_boundary.zip',expected_archive_bytes=18108565,
    expected_archive_sha256='8197e332342eb83b536863e340aabbe3a23e90752522438ee25ef1f4ba584aee',
    source_content_reads=0,source_decoding=0,source_writes=0,new_jobs=0,downloads=0,
    model_calls=0,automatic_checks_enabled=False,archive_candidates=[],fixed={},errors=[],complete=False)
try:
    assert BASE.resolve(strict=True)==BASE and BASE.is_dir()
    todo=[(BASE,0)];entries=0;directories=0
    while todo:
        parent,depth=todo.pop(0);directories+=1
        assert directories<=512 and time.monotonic()-START<45,'Inventory limit'
        with os.scandir(parent) as it:
            for entry in it:
                entries+=1
                assert entries<=5000 and time.monotonic()-START<45,'Inventory limit'
                if entry.is_symlink():continue
                if entry.name=='0_catchment_boundary.zip' and entry.is_file(follow_symlinks=False):
                    s=entry.stat(follow_symlinks=False)
                    result['archive_candidates'].append(dict(path=entry.path,bytes=s.st_size,mtime_ns=s.st_mtime_ns))
                if depth<2 and entry.name not in result['excluded_directory_names'] and entry.is_dir(follow_symlinks=False):
                    todo.append((Path(entry.path),depth+1))
    result.update(entries=entries,directories=directories,complete=True)
except Exception as e:result['errors'].append(dict(stage='bounded_inventory',type=type(e).__name__,message=str(e)[:1000]))
for name,value in FIXED.items():
    path=Path(value)
    try:
        assert not path.is_symlink()
        s=path.stat();result['fixed'][name]=dict(path=value,exists=True,is_file=path.is_file(),bytes=s.st_size,mtime_ns=s.st_mtime_ns)
    except Exception as e:result['fixed'][name]=dict(path=value,exists=False,error_type=type(e).__name__,message=str(e)[:500])
result.update(seconds=time.monotonic()-START,server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
raw=(json.dumps(result,ensure_ascii=False,allow_nan=False,separators=(',',':'))+'\n').encode()
assert len(raw)<1048576
print('GEOLOGY_RECOVERY_BYTES='+str(len(raw)))
print('GEOLOGY_RECOVERY_SHA256='+hashlib.sha256(raw).hexdigest())
print('GEOLOGY_RECOVERY_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode())
print('GEOLOGY_RECOVERY_DONE')

PATH_INVENTORY
