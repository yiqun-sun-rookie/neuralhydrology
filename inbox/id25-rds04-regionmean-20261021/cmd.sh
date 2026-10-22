#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - "$root" <<'PYHEADER'
import hashlib,json,re,sys
from pathlib import Path
r=Path(sys.argv[1]); stage=r/'resource_compatibility_v003'
assert str(r)=='/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001'
assert (r/'job_id.txt').read_text().strip()=='246090'
p=stage/'apply_result.json'
if p.exists() and json.loads(p.read_text()).get('state')=='CPU_EXECUTION_PARTITIONS_EXPANDED':
    script=r/'hpc/train.slurm'; before=script.read_bytes()
    after=re.sub(br'(?m)^#SBATCH -p [^\r\n]+',b'#SBATCH -p hgpu2p,hcpu48y',before)
    if after!=before:
        backup=stage/'train_before_resume_header_fix.slurm'
        assert not backup.exists(),'Unexpected duplicate header mutation'
        backup.write_bytes(before)
        temp=script.with_suffix('.slurm.resource_pending'); temp.write_bytes(after); temp.replace(script)
        result={'scope':'future_technical_resume_header_only','partitions':['hgpu2p','hcpu48y'],'reason':'avoid recreating EXCLUSIVE partition whole-node flag on future technical resume','before_sha256':hashlib.sha256(before).hexdigest(),'after_sha256':hashlib.sha256(after).hexdigest(),'training_body_unchanged':re.sub(br'(?m)^#SBATCH -p [^\r\n]+',b'',before)==re.sub(br'(?m)^#SBATCH -p [^\r\n]+',b'',after),'current_job_mutated':False,'new_submissions':0}
        assert result['training_body_unchanged']
        (stage/'resume_header_fix.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result))
PYHEADER
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
date -Is
for rel in job_id.txt submissions.tsv; do echo "FILE=$rel"; if test -f "$root/$rel"; then cat "$root/$rel"; fi; done
if test -f "$root/job_id.txt"; then
 job=$(cat "$root/job_id.txt")
 timeout 30 squeue -h -j "$job" -o '%i|%j|%T|%M|%R' || true
 timeout 30 sacct -n -X -j "$job" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList -P
fi
for rel in runtime.json output/status.json output/selection.json report.json; do
 echo "FILE=$rel"; if test -f "$root/$rel"; then cat "$root/$rel"; fi
done
if test -f "$root/output/metrics.jsonl"; then tail -n 2 "$root/output/metrics.jsonl"; fi
for f in "$root"/logs/*.out "$root"/logs/*.err; do if test -f "$f"; then echo "LOG=$f"; tail -n 12 "$f"; fi; done

timeout 30 scontrol -o show job 246090 || true
timeout 30 squeue --start -j 246090 -o '%i|%T|%r|%S|%Q|%R' || true
