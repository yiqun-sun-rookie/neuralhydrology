#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import hashlib,io,json,pathlib,tarfile
payload=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf/payload_complete_comparison_20261006_147.tar.gz')
raw=payload.read_bytes()
if hashlib.sha256(raw).hexdigest()!='761cdd240f954fde3e361ae721c537b1390afd64b436e8e29ba33b781ac7ae04': raise ValueError('release archive identity differs')
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_001')
if root.exists(): raise FileExistsError('preserve existing release and jobs')
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as tar:
    members=tar.getmembers()
    if len({m.name for m in members})!=len(members): raise ValueError('duplicate release member')
    for member in members:
        p=pathlib.PurePosixPath(member.name)
        if p.is_absolute() or '..' in p.parts or not member.isfile(): raise ValueError('unsafe release entry')
    content={m.name:tar.extractfile(m).read() for m in members}
manifest=json.loads(content.pop('release_manifest.json'))
if set(manifest['files'])!=set(content): raise ValueError('release allow-list differs')
for name,data in content.items():
    spec=manifest['files'][name]
    if len(data)!=spec['bytes'] or hashlib.sha256(data).hexdigest()!=spec['sha256']: raise ValueError('release file changed')
root.mkdir()
for name,data in content.items():
    p=root/name; p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(data)
(root/'release_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for name in ('logs','runs','reports','predictions','artifacts'): (root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'code_release_verified','code_hash':manifest['code_hash'],'files':len(content)}))
PY
cd /data1/home/sunyiq/zhenjiang_complete_comparison_20261006_001
export PYTHONDONTWRITEBYTECODE=1
python3 - <<'PY'
import json,pathlib
p=pathlib.Path('records/scheduler_submission_started.json')
with p.open('x') as f: json.dump({'status':'single_submission_attempt','evaluation_authorized':False},f)
PY
parse_job() {
    local receipt="$1"
    local last_line
    last_line=$(printf '%s\n' "$receipt" | tail -n 1)
    if [[ "$receipt" =~ Submitted[[:space:]]batch[[:space:]]job[[:space:]]([0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    elif [[ "$last_line" =~ ^([0-9]+)(\;[a-zA-Z0-9_.-]+)?$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf 'Unrecognized scheduler receipt; preserve attempt and inspect jobs.\n' >&2
        return 1
    fi
}
prep_receipt=$(xbatch --parsable hpc/prepare_data.sbatch)
printf '%s\n' "$prep_receipt" > records/preparation_scheduler_receipt.txt
prep_job=$(parse_job "$prep_receipt")
[[ "$prep_job" =~ ^[0-9]+$ ]]
for case_name in legacy_lstm__small explicit_gru__small legacy_lstm__historical_capacity explicit_gru__historical_capacity; do
    receipt=$(xbatch --parsable --dependency=afterok:"$prep_job" --job-name="zj_${case_name}_261006" hpc/train_case.sbatch "$case_name")
    printf '%s\n' "$receipt" > "records/scheduler_${case_name}.txt"
    job=$(parse_job "$receipt")
    printf 'TRAINING_CASE %s JOB %s\n' "$case_name" "$job"
done
printf 'PREPARATION_JOB %s\n' "$prep_job"
squeue -u sunyiq -h -o '%i|%j|%T|%R'
