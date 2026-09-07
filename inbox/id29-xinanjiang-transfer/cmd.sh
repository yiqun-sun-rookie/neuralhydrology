#!/bin/bash
# Deploy exactly the independently reviewed immutable bundle and submit only its technical gate.
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/inbox/id29-xinanjiang-transfer/xinanjiang_bundle.tar.gz
EXPECTED_ARCHIVE=9fe368bf376d0f0d90858a52d964e231e0a04794429990e33325007743f4acac
EXPECTED_MANIFEST=59a8f8b50776086c5b1263e441cfc9cf80299b80feca24a60919d582d5d21545
test ! -e "$TASK_ROOT" || { echo 'STOP: experiment root already exists'; exit 11; }
test -d /data1/home/sunyiq/neuralhydrology/data/camels_us || exit 12
test -f "$PAYLOAD" || exit 13
printf '%s  %s\n' "$EXPECTED_ARCHIVE" "$PAYLOAD" | sha256sum -c -
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - "$PAYLOAD" "$TASK_ROOT" "$EXPECTED_MANIFEST" <<'PY'
import hashlib,json,pathlib,sys,tarfile
archive,root,expected=sys.argv[1],pathlib.Path(sys.argv[2]),sys.argv[3]
with tarfile.open(archive,'r:gz') as tar:
    members=tar.getmembers()
    names=[m.name for m in members]
    if len(names)!=len(set(names)):
        raise ValueError('duplicate archive paths')
    for member in members:
        path=pathlib.PurePosixPath(member.name)
        if not member.isfile() or path.is_absolute() or '..' in path.parts or path.parts[0]!='bundle':
            raise ValueError('unsafe archive member')
    root.mkdir(exist_ok=False)
    tar.extractall(root)
manifest=root/'bundle/MANIFEST.json'
if hashlib.sha256(manifest.read_bytes()).hexdigest()!=expected:
    raise ValueError('manifest identity mismatch')
entries=json.loads(manifest.read_text())
for name,digest in entries.items():
    path=(root/'bundle'/name)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
        raise ValueError('bundle file mismatch: '+name)
(root/'logs').mkdir()
print('BUNDLE_VERIFIED',len(entries),expected)
PY
cd "$TASK_ROOT/bundle"
SUBMITTED_JOB=$(sbatch --parsable src/xinanjiang_transfer_noise/hpc/pilot.slurm)
printf '%s\n' "$SUBMITTED_JOB" > "$TASK_ROOT/pilot_job_id.txt"
printf 'SUBMITTED_TECHNICAL_JOB=%s\n' "$SUBMITTED_JOB"
squeue -j "${SUBMITTED_JOB%%;*}" -o '%.18i %.12j %.10T %.10M %.6D %R'
printf 'DEPLOYMENT_COMPLETE\n'
