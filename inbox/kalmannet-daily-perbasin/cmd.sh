#!/bin/bash
# channel=kalmannet-daily-perbasin sequence=78 read-only observation
set -uo pipefail
task_sequence=78
task_job=224117
[[ "$task_sequence" =~ ^[1-9][0-9]*$ && "$task_job" =~ ^[1-9][0-9]*$ ]] || exit 80
printf 'channel=kalmannet-daily-perbasin sequence=%s purpose=read-only-first-training-job%s-metadata\n' "$task_sequence" "$task_job"
task_root=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908
task_request=$task_root/runtime/train_08190500_seq77
for task_path in /data1 /data1/home /data1/home/sunyiq "$task_root" "$task_root/runtime" "$task_request" "$task_root/runs"; do
  [[ -d "$task_path" && ! -L "$task_path" && "$(readlink -f -- "$task_path")" == "$task_path" ]] || exit 81
done
printf '%s\n' 'QUERY_PARENT_JOB_BEGIN'
timeout 20s scontrol show job -dd "$task_job"
printf 'QUERY_PARENT_JOB_EXIT=%s\n' "$?"
printf '%s\n' 'QUERY_QUEUE_BEGIN'
timeout 20s squeue -r -h -j "$task_job" -o '%i|%j|%T|%M|%l|%D|%C|%b|%N|%R'
printf 'QUERY_QUEUE_EXIT=%s\n' "$?"
printf '%s\n' 'QUERY_PARENT_ACCOUNTING_BEGIN'
timeout 20s sacct -X -n -P -j "$task_job" --format=JobIDRaw,JobName,State,ExitCode,ElapsedRaw,AllocCPUS,ReqTRES,AllocTRES,NodeList,Submit,Start,End
printf 'QUERY_PARENT_ACCOUNTING_EXIT=%s\n' "$?"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - "$task_job" <<'KNET_READ_ONLY_SMALL_METADATA'
import base64, hashlib, os, pathlib, re, stat, sys
job = sys.argv[1]
if not re.fullmatch(r'[1-9][0-9]*', job):
    raise ValueError('confirmed positive job identifier required')
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908')
request = root / 'runtime/train_08190500_seq77'
run = root / 'runs/DAILY_CAMELS_KNET_PER_BASIN_21_DEVELOPMENT_V2_20260908_BASIN_08190500_A800_TRAIN1_SEQ77'
targets = [request / name for name in (
    'submission_seq77.attempt', 'submission_seq77.stdout', 'submission_seq77.stderr',
    f'slurm-{job}.stdout', f'slurm-{job}.stderr', 'execution_ownership.json',
    'submission_livecheck_seq77/success.json', 'submission_livecheck_seq77/failure.json',
    'evidence/worker_result.json', 'evidence/audit/independent_verification_report.json')]
targets += [request / 'evidence' / stage / name
            for stage in ('environment_probe', 'training_process', 'verifier_process')
            for name in ('launch.json', 'terminal.json', 'stdout.bin', 'stderr.bin')]
targets += [run / name for name in ('preflight.json', 'epoch_history.json',
    'divergence_event.json', 'unregistered_numeric_failure_event.json', 'result_summary.json',
    'completion.marker.json')]
total = 0
for path in targets:
    if not path.is_relative_to(root) or '..' in path.parts:
        raise ValueError('foreign metadata target')
    try:
        info = path.lstat()
    except FileNotFoundError:
        print('METADATA_ABSENT ' + str(path), flush=True)
        continue
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise ValueError('unsafe metadata target: ' + str(path))
    for ancestor in path.parents:
        parent = ancestor.lstat()
        if not stat.S_ISDIR(parent.st_mode) or stat.S_ISLNK(parent.st_mode):
            raise ValueError('unsafe metadata ancestor: ' + str(ancestor))
    if path.resolve(strict=True) != path:
        raise ValueError('noncanonical metadata path')
    if info.st_size > 262144 or total + info.st_size > 450000:
        print(f'METADATA_CONTENT_OMITTED_SIZE bytes={info.st_size} {path}', flush=True)
        continue
    with path.open('rb') as handle:
        before = os.fstat(handle.fileno())
        raw = handle.read(262145)
        after = os.fstat(handle.fileno())
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns) or len(raw) != after.st_size:
        print('METADATA_CHANGED_DURING_READ ' + str(path), flush=True)
        continue
    if len(raw) > 262144 or total + len(raw) > 450000:
        print(f'METADATA_CONTENT_OMITTED_SIZE bytes={len(raw)} {path}', flush=True)
        continue
    total += len(raw)
    print(f'METADATA_FILE bytes={len(raw)} sha256_and_path={hashlib.sha256(raw).hexdigest()}  {path}', flush=True)
    print('METADATA_BASE64_BEGIN ' + str(path), flush=True)
    print(base64.b64encode(raw).decode('ascii'), flush=True)
    print('METADATA_BASE64_END ' + str(path), flush=True)
print(f'READ_ONLY_OBSERVATION_COMPLETE metadata_bytes={total} submissions=0 checkpoints_read=0 scientific_arrays_read=0', flush=True)
KNET_READ_ONLY_SMALL_METADATA

