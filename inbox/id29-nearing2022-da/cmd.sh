#!/bin/bash
# ID29 seq=41: two-hour status probe. Short, read-only, no waiting.
echo "=== QUEUE ==="
squeue -j 201890,201893 -o "%.10i %.10j %.10T %.12M" 2>&1

echo "=== ACCOUNTING ==="
sacct -j 201890,201893 -X --format=JobID%10,JobName%12,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== HEADLINE TABLE ==="
TABLE=/data1/home/sunyiq/nearing2022_da/results/29_nearing2022_da_ar/headline_table.csv
if [ -f "$TABLE" ]; then
    cat "$TABLE"
else
    echo "NOT_PRESENT"
fi
