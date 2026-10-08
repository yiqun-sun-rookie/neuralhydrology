#!/usr/bin/env bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'PY'
import sys,json,hashlib,os,datetime,re,inspect
from pathlib import Path
import numpy as np
prefix=Path("/data1/home/sunyiq/miniconda3/envs/nh_final").resolve(strict=True)
if Path(sys.prefix).resolve(strict=True)!=prefix:raise RuntimeError("Interpreter prefix differs")
if Path(sys.executable).resolve(strict=True)!= (prefix/"bin/python").resolve(strict=True):raise RuntimeError("Interpreter identity differs")
if not Path(np.__file__).resolve(strict=True).is_relative_to(prefix):raise RuntimeError("NumPy outside original prefix")
def metadata(p):
 p=p.resolve(strict=True)
 if not p.is_relative_to(prefix.resolve(strict=True)):raise RuntimeError("Outside original interpreter prefix")
 st=p.stat()
 if not p.is_file():raise RuntimeError("Not regular metadata file")
 raw=p.read_bytes()
 if len(raw)>4194304:raise RuntimeError("Oversized metadata")
 return {"path":str(p),"bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest(),"mtime_utc":datetime.datetime.fromtimestamp(st.st_mtime,datetime.timezone.utc).isoformat()},raw
records=[]
for p in sorted((prefix/"conda-meta").glob("numpy-*.json")):
 meta,raw=metadata(p)
 package=json.loads(raw)
 meta["package"]={k:package.get(k) for k in ("name","version","build","build_number","timestamp","subdir")}
 records.append(meta)
history_meta,history=metadata(prefix/"conda-meta/history")
lines=history.decode("utf-8").splitlines()
sections=[];transaction=None
for line in lines:
 if re.fullmatch(r"==> [0-9 :\\-]+ <==",line):transaction=line
 if line.startswith(("+","-")):
  suffix=line[1:].rsplit("::",1)[-1]
  if re.fullmatch(r"numpy-[A-Za-z0-9._\\-]+",suffix):
   sections.append({"transaction":transaction,"action":line[0],"package":suffix})
quantile_source=inspect.getsource(np.quantile)
if len(quantile_source)>65536:raise RuntimeError("Oversized quantile source")
source_module=__import__(np.quantile.__module__,fromlist=["_lerp"])
lerp_source=inspect.getsource(source_module._lerp) if hasattr(source_module,"_lerp") else None
wet=np.zeros(848,dtype=np.float32)
wet[:839]=np.float32(32.189998626708984)
wet[839:]=np.float32(32.2400016784668)
print(json.dumps({"kind":"read_only_original_interpreter_metadata_v1","observed_at_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"python_executable":sys.executable,"python_version":sys.version,"numpy_version":np.__version__,"numpy_file":np.__file__,"numpy_conda_records":records,"quantile_source_sha256":hashlib.sha256(quantile_source.encode()).hexdigest(),"lerp_source":lerp_source,"conda_history_metadata":history_meta,"numpy_history_sections":sections,"fixed_synthetic_quantile":float(np.quantile(wet,.99,method="linear")),"original_job_numpy_version_not_inferred_without_history_evidence":True,"science_inputs_read":False,"weights_loaded":False,"scores_read":False,"jobs_submitted":False},sort_keys=True))
PY

