#!/bin/bash
set -o pipefail
date --iso-8601=seconds
sacct -X -n -P -j 245671,245672,245673,245674 --format=JobID,JobName,State,ExitCode,Elapsed 2>/dev/null
exit 0
