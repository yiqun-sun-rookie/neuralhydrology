#!/bin/bash
# OPS recovery: export 241344 failed in 11 s after my move to hcpu48 (CentOS 7 glibc 2.17 cannot load the frozen torch 2.7.1 runtime).
# Resubmit the SAME export on hgpu2p (Rocky 9.5). Copy of export.sbatch with only the gpu request and the satisfied
# afterany:241337 dependency removed (export reads records/hashes only). Fallback: identical GPU request. Science unchanged.
set -u
W=/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/workflow_v010_20261012_001
echo "RS_TIME $(date -u +%FT%TZ)"
sacct -j 241344,241345 -X -n -P -o JobID,JobName,State,ExitCode,Elapsed,Partition,NodeList 2>&1
[ "$(sacct -j 241344 -X -n -P -o State)" = FAILED ] || { echo RS_241344_NOT_FAILED_NO_CHANGE; exit 3; }
[ ! -e $W/hpc_packet_001 ] || { echo RS_PACKET_EXISTS_NO_CHANGE; exit 3; }
[ -z "$(squeue -u $USER -h -n hydrol85935-v010-export -o %i)" ] || { echo RS_EXPORT_ALREADY_QUEUED_NO_CHANGE; exit 3; }
sha256sum $W/export.sbatch
N=$W/export_hgpu2p_cpu_20261023.sbatch; G=$W/export_hgpu2p_gpu_20261023.sbatch
[ ! -e $N ] && [ ! -e $G ] || { echo RS_NEW_SCRIPT_EXISTS_NO_CHANGE; exit 3; }
grep -v -x -e '#SBATCH --gres=gpu:1' -e '#SBATCH --dependency=afterany:241337' $W/export.sbatch > $N
grep -v -x -e '#SBATCH --dependency=afterany:241337' $W/export.sbatch > $G
echo RS_DIFF_CPU; diff $W/export.sbatch $N; echo RS_DIFF_GPU; diff $W/export.sbatch $G
[ "$(diff $W/export.sbatch $N | grep -c '^<')" = 2 ] && [ "$(diff $W/export.sbatch $G | grep -c '^<')" = 1 ] || { echo RS_DIFF_UNEXPECTED_NO_SUBMIT; exit 3; }
sha256sum $N $G
cd $W
echo RS_TEST_CPU; sbatch --test-only $N 2>&1
out=$(sbatch $N 2>&1); echo "RS_SUBMIT_CPU $out"
id=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+$')
if [ -z "$id" ]; then out=$(sbatch $G 2>&1); echo "RS_SUBMIT_GPU $out"; id=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+$'); fi
[ -n "$id" ] || { echo RS_SUBMIT_FAILED; exit 4; }
echo "RS_JOB $id"; sleep 45
squeue -j $id -h -o "%i|%j|%T|%r|%P|%b|%S|%N" 2>&1; sacct -j $id -X -n -P -o JobID,State,Start,NodeList 2>&1
exit 0
