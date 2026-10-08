#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import pathlib,json,hashlib,subprocess,re,base64
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
source=root/'hpc/pathfix_legacy_lstm__small.slurm';raw=source.read_bytes()
if hashlib.sha256(raw).hexdigest()!='0006d552d49e2313b0f2b63224073feae2b4f2e797e4769ff530a882cf429f5b':raise ValueError('valid pathfix source changed')
program=root/'hpc/gpu_compatibility_20261008.py'
with program.open('xb') as f:f.write(base64.b64decode('aW1wb3J0IHRvcmNoLCBwYXRobGliLCBqc29uLCBvcywgZGF0ZXRpbWUKcm9vdD1wYXRobGliLlBhdGgoJy9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDInKQpwPXRvcmNoLmN1ZGEuZ2V0X2RldmljZV9wcm9wZXJ0aWVzKDApCmE9dG9yY2gudGVuc29yKFsuMSwtLjIsLjNdLGRldmljZT0nY3VkYScpO2I9KGEqYSkuc3VtKCk7dG9yY2guY3VkYS5zeW5jaHJvbml6ZSgpCnI9eydzdGF0dXMnOidzeW50aGV0aWNfZ3B1X2NvbXBhdGliaWxpdHlfcHJvYmUnLCdqb2JfaWQnOm9zLmVudmlyb25bJ1NMVVJNX0pPQl9JRCddLCdub2RlJzpvcy5lbnZpcm9uLmdldCgnU0xVUk1EX05PREVOQU1FJyksJ2RldmljZV9pZGVudGl0eSc6eydkZXZpY2UnOidjdWRhOjAnLCduYW1lJzpwLm5hbWUsJ3RvdGFsX21lbW9yeV9ieXRlcyc6cC50b3RhbF9tZW1vcnl9LCdtYXRjaGVzX2Zyb3plbl9kZXZpY2UnOnAubmFtZT09J05WSURJQSBHZUZvcmNlIFJUWCAzMDkwJyBhbmQgcC50b3RhbF9tZW1vcnk9PTI1Mjk2MDQ0MDMyLCdzY2FsYXJfcmVzdWx0JzpmbG9hdChiKSwncmVhbF90cmFpbmluZ19zdGFydGVkJzpGYWxzZSwnZXZhbHVhdGlvbl92YWx1ZXNfcmVhZCc6RmFsc2UsJ2NoZWNrZWRfYXQnOmRhdGV0aW1lLmRhdGV0aW1lLm5vdygpLmFzdGltZXpvbmUoKS5pc29mb3JtYXQoKX0KcGF0aD1yb290LydyZWNvcmRzL21vbml0b3JpbmdfM2gnLygnZ3B1X2NvbXBhdGliaWxpdHlfJytyWydqb2JfaWQnXSsnLmpzb24nKQp3aXRoIHBhdGgub3BlbigneCcpIGFzIGY6anNvbi5kdW1wKHIsZixpbmRlbnQ9MikKcHJpbnQoanNvbi5kdW1wcyhyKSxmbHVzaD1UcnVlKQo='))
body=raw.decode().splitlines();out=[]
for line in body:
 if line.startswith('#SBATCH --job-name='):line='#SBATCH --job-name=zj_gpu_compatibility_261008_007'
 elif line.startswith('#SBATCH --dependency='):continue
 elif line.startswith('#SBATCH --exclude='):line='#SBATCH --exclude=ngu002,ngu011'
 elif line.startswith('case_name='):continue
 elif line.startswith('python -B -u scripts/train_supercomputer_case.py'):line='python -B -u hpc/gpu_compatibility_20261008.py'
 out.append(line)
out.insert(2,'#SBATCH --nodelist=ngu007');body='\n'.join(out)+'\n';script=root/'hpc/gpu_compatibility_20261008_007.slurm'
with script.open('x') as f:f.write(body)
p=root/'records/monitoring_3h/gpu_compatibility_submission_007_attempt.json'
with p.open('x') as f:json.dump({'status':'reserved','script':str(script),'source_pathfix_sha256':'0006d552d49e2313b0f2b63224073feae2b4f2e797e4769ff530a882cf429f5b','script_sha256':hashlib.sha256(script.read_bytes()).hexdigest()},f,indent=2)
r=subprocess.run(['/usr/local/globle/softs/slurm/19.05.4.1/bin/xbatch',str(script)],capture_output=True,text=True,timeout=45)
report={'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'real_training_started':False}
with (root/'records/monitoring_3h/gpu_compatibility_submission_007_response.json').open('x') as f:json.dump(report,f,indent=2)
match=re.fullmatch(r'Submitted batch job ([0-9]+)\s*',r.stdout)
if r.returncode or not match:raise RuntimeError('compatibility probe submission uncertain; inspect without resubmitting')
report['job_id']=match.group(1);print(json.dumps(report,ensure_ascii=True))
PY
