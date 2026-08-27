#!/usr/bin/env bash
set -euo pipefail
squeue -h -j 215649 -o '%A|%j|%P|%T|%R|%b|%Z|%o'
sacct -j 215649 --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocTRES,ReqTRES
