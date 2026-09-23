#!/bin/bash
set -eo pipefail

echo 'TUKF09_HCPU48Y_ACCOUNTING_QUERY_V1_BEGIN'
echo 'query_kind=read_only_no_submission_no_model'
date -u '+query_time_utc=%Y-%m-%dT%H:%M:%SZ'
hostname

echo 'PARTITION_HCPU48Y_BEGIN'
scontrol show partition hcpu48y -o
echo 'PARTITION_HCPU48Y_END'

echo 'JOB_227288_ACCOUNTING_BEGIN'
sacct -X -j 227288 -P -n --format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode
echo 'JOB_227288_ACCOUNTING_END'

echo 'JOB_227288_CONTROL_BEGIN'
scontrol show job -dd 227288 -o || true
echo 'JOB_227288_CONTROL_END'

echo 'TUKF09_HCPU48Y_ACCOUNTING_QUERY_V1_END'
