#!/bin/bash
# a02b seq=11 : capture the per-job node assignment record required by the
# pre-registered plan (arm-by-node confound check). sacct retention is finite.
export LC_ALL=C
echo "##BEGIN_JSONL"
timeout 60 sacct -S 2026-08-07 -u "$USER" -X -P -n \
  --format=JobID,JobName,NodeList,Partition,State,ExitCode,Elapsed,Start,End,ReqTRES,AllocTRES 2>&1 \
  | grep -E "^[0-9]+\|a02_(pre|sam)"
echo "##END_JSONL"
echo "##FIELDS JobID|JobName|NodeList|Partition|State|ExitCode|Elapsed|Start|End|ReqTRES|AllocTRES"
echo "##GPUMODEL"
for n in $(timeout 60 sacct -S 2026-08-07 -u "$USER" -X -P -n --format=NodeList 2>&1 | grep -E "^ngu" | sort -u); do
  m=$(timeout 20 scontrol show node "$n" 2>/dev/null | grep -o "Gres=gpu:[^ ]*" | head -1)
  echo "  $n ${m:-unknown}"
done
