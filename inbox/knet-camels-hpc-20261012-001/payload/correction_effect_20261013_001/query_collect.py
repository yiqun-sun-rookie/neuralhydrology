"""Own job accounting, progress and bounded artifact collection; no model compute."""
import sys,os,json,datetime,subprocess,hashlib,tarfile,io,base64,importlib.util
from pathlib import Path
BASE=Path(sys.argv[1]);job=sys.argv[2]
if not job.isdigit():raise RuntimeError('invalid job number')
sp=importlib.util.spec_from_file_location('safe_io',BASE/'safe_io.py');s=importlib.util.module_from_spec(sp);sp.loader.exec_module(s)
accounting=subprocess.run(['sacct','-j',job,'--noheader','--parsable2','--format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,Partition,NodeList,Start,End'],capture_output=True,text=True,check=True).stdout
rows=[line for line in accounting.splitlines() if line];attempts=[];files=[]
if (BASE/'runs').is_dir():
 for folder in sorted((BASE/'runs').iterdir()):
  if not folder.is_dir() or not folder.name.startswith('attempt_'):continue
  rp=folder/'receipt.json';receipt=json.loads(s.read_checked(rp)) if rp.is_file() else None
  attempts.append({'name':folder.name,'receipt':receipt})
  for path in sorted(folder.iterdir()):
   if path.is_file():files.append(path)
log=BASE/'logs'/('diagnostic-'+job+'.out');error=BASE/'logs'/('diagnostic-'+job+'.err');events=[]
if log.is_file():
 for line in s.read_checked(log).decode('utf-8',errors='replace').splitlines():
  try:obj=json.loads(line)
  except ValueError:continue
  if 'event' in obj:events.append(obj)
 files.append(log)
if error.is_file():files.append(error)
status={'job_id':job,'queried_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'accounting':rows,'attempts':attempts,'progress':events,'job_log_last_lines':s.read_checked(log).decode('utf-8',errors='replace').splitlines()[-18:] if log.is_file() and not any(x.get('receipt') and x['receipt']['status']=='COMPLETED' for x in attempts) else []}
print('JOB_STATUS_JSON='+json.dumps(status,ensure_ascii=False))
terminal=any(line.split('|')[0]==job and line.split('|')[2].split()[0] in ['COMPLETED','FAILED','CANCELLED','TIMEOUT','NODE_FAIL','OUT_OF_MEMORY'] for line in rows)
if terminal:
 stream=io.BytesIO();manifest=[]
 with tarfile.open(fileobj=stream,mode='w:gz') as tar:
  for path in files:
   raw=s.read_checked(path);name=str(path.relative_to(BASE));item=tarfile.TarInfo(name);item.size=len(raw);item.mode=0o644;item.mtime=0;tar.addfile(item,io.BytesIO(raw));manifest.append({'path':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()})
  record=(json.dumps({'job_id':job,'accounting':rows,'files':manifest,'captured_utc':status['queried_utc']},ensure_ascii=False,indent=2)+'\n').encode();item=tarfile.TarInfo('collection_manifest_'+job+'.json');item.size=len(record);item.mode=0o644;item.mtime=0;tar.addfile(item,io.BytesIO(record))
 payload=stream.getvalue();print('ARTIFACT_ARCHIVE_METADATA='+json.dumps({'job_id':job,'files':len(files)+1,'bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest()}));print('ARTIFACT_ARCHIVE_BASE64='+base64.b64encode(payload).decode())
