#!/bin/bash
set -uo pipefail
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=75 purpose=read-only-precheck-job224110-metadata'
task_root=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908
task_request=$task_root/runtime/precheck_seq73
task_output=$task_root/prechecks/precheck_seq73
for task_path in /data1 /data1/home /data1/home/sunyiq "$task_root" "$task_root/runtime" "$task_request" "$task_root/prechecks"; do
  [[ -d "$task_path" && ! -L "$task_path" && "$(readlink -f -- "$task_path")" == "$task_path" ]] || exit 81
done
printf '%s\n' 'QUERY_PARENT_JOB_BEGIN'
scontrol show job -dd 224110
printf 'QUERY_PARENT_JOB_EXIT=%s\n' "$?"
printf '%s\n' 'QUERY_QUEUE_BEGIN'
squeue -r -h -j 224110 -o '%i|%j|%T|%M|%l|%D|%C|%b|%N|%R'
printf 'QUERY_QUEUE_EXIT=%s\n' "$?"
printf '%s\n' 'QUERY_PARENT_ACCOUNTING_BEGIN'
sacct -X -n -P -j 224110 --format=JobIDRaw,JobName,State,ExitCode,ElapsedRaw,AllocCPUS,ReqTRES,AllocTRES,NodeList,Submit,Start,End
printf 'QUERY_PARENT_ACCOUNTING_EXIT=%s\n' "$?"
task_total=0
task_emit_metadata() {
  local task_file=$1 task_size task_digest
  [[ "$task_file" == "$task_root/"* ]] || return 81
  if [[ ! -e "$task_file" && ! -L "$task_file" ]]; then printf 'METADATA_ABSENT %s\n' "$task_file"; return 0; fi
  [[ -f "$task_file" && ! -L "$task_file" && "$(readlink -f -- "$task_file")" == "$task_file" ]] || { printf 'METADATA_UNSAFE %s\n' "$task_file"; return 82; }
  task_size=$(stat -c '%s' -- "$task_file") || return 83
  task_digest=$(sha256sum -- "$task_file") || return 84
  printf 'METADATA_FILE bytes=%s sha256_and_path=%s\n' "$task_size" "$task_digest"
  if ((task_size>393216 || task_total+task_size>650000)); then printf 'METADATA_CONTENT_OMITTED_SIZE %s\n' "$task_file"; return 0; fi
  task_total=$((task_total+task_size))
  printf 'METADATA_BASE64_BEGIN %s\n' "$task_file"
  base64 --wrap=0 -- "$task_file" || return 85
  printf '\nMETADATA_BASE64_END %s\n' "$task_file"
}
for task_name in submission_seq73.attempt submission_seq73.stdout submission_seq73.stderr slurm-224110.stdout slurm-224110.stderr submission_livecheck_seq73/success.json submission_livecheck_seq73/failure.json; do
  task_emit_metadata "$task_request/$task_name" || exit "$?"
done
for task_name in worker_result.json runtime_environment/stdout.json runtime_environment/stderr.txt runtime_environment/process.json; do
  task_emit_metadata "$task_output/$task_name" || exit "$?"
done
for task_basin in 08190500 02102908 12447390 01487000 02178400 09513780 06803510 03076600 12175500 04027000 08109700 08086290 01440400 05503800 03049000 01435000 02092500 14185900; do
  for task_name in stdout.json stderr.txt process.json validation.json; do
    task_emit_metadata "$task_output/$task_basin/$task_name" || exit "$?"
  done
done
printf 'READ_ONLY_OBSERVATION_COMPLETE metadata_bytes=%s submissions=0 checkpoints_read=0 scientific_arrays_read=0\n' "$task_total"
