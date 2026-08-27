#!/usr/bin/env bash
set -u
squeue -h -j 215699 -o '%A|%j|%P|%T|%R|%b|%Z|%o' || true
sacct -j 215699 --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocTRES,ReqTRES
