#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_graice_lstmnosif_20261015_001
test "$(cat "$root/job_id.txt")" = 242767
active=$(squeue -h -u sunyiq -n id25_graice_261015 -o '%i')
if [ -n "$active" ]; then echo OWN_JOB_STILL_ACTIVE; exit 1; fi
state=$(sacct -j 242767 --format=JobIDRaw,State -n -P | awk -F '|' '$1==242767 {print $2}')
test "$state" = FAILED
export PIP_CACHE_DIR="$root/pip_cache"
export PYTHONNOUSERSITE=1
unset PYTHONPATH
if ! "$root/venv/bin/python" -m pip install --no-input --only-binary=:all: tensorflow-cpu==2.15.1 numpy==1.26.4 scipy==1.12.0 scikit-learn==1.4.2 matplotlib==3.8.4 > "$root/logs/env_install_v002.log" 2>&1; then
  tail -n 25 "$root/logs/env_install_v002.log"
  exit 1
fi
"$root/venv/bin/python" -m pip freeze > "$root/runtime_requirements.txt"
touch "$root/venv/runtime_ready"
new="$root/code/hpc/graice_lstmnosif_b02_20261015_v002.slurm"
test ! -e "$new"
printf '%s' 'IyEvdXNyL2Jpbi9lbnYgYmFzaAojU0JBVENIIC1KIGlkMjVfZ3JhaWNlXzI2MTAxNQojU0JBVENIIC1wIGhncHUycAojU0JBVENIIC1OIDEKI1NCQVRDSCAtbiAxCiNTQkFUQ0ggLS1jcHVzLXBlci10YXNrPTQKI1NCQVRDSCAtLWV4Y2x1ZGU9bmd1MDAyCiNTQkFUQ0ggLXQgMTI6MDA6MDAKI1NCQVRDSCAtbyAvZGF0YTEvaG9tZS9zdW55aXEvaWQyNV9ncmFpY2VfbHN0bW5vc2lmXzIwMjYxMDE1XzAwMS9sb2dzL2dyYWljZS0lai5vdXQKI1NCQVRDSCAtZSAvZGF0YTEvaG9tZS9zdW55aXEvaWQyNV9ncmFpY2VfbHN0bW5vc2lmXzIwMjYxMDE1XzAwMS9sb2dzL2dyYWljZS0lai5lcnIKc2V0IC1lbyBwaXBlZmFpbApyb290PS9kYXRhMS9ob21lL3N1bnlpcS9pZDI1X2dyYWljZV9sc3Rtbm9zaWZfMjAyNjEwMTVfMDAxCiMgQ1BVLW9ubHkgc21hbGwgbW9kZWxzOiByZXF1ZXN0IHNwYXJlIENQVSBjb3Jlcywgbm8gR1BVIHJlc2VydmF0aW9uLgpleHBvcnQgTUtMX1RIUkVBRElOR19MQVlFUj1HTlUKZXhwb3J0IE1LTF9TRVJWSUNFX0ZPUkNFX0lOVEVMPTEKZXhwb3J0IE9NUF9OVU1fVEhSRUFEUz00CmV4cG9ydCBNS0xfTlVNX1RIUkVBRFM9NApleHBvcnQgT1BFTkJMQVNfTlVNX1RIUkVBRFM9NApleHBvcnQgQ1VEQV9WSVNJQkxFX0RFVklDRVM9LTEKZXhwb3J0IFRGX0VOQUJMRV9PTkVETk5fT1BUUz0wCmV4cG9ydCBURl9DUFBfTUlOX0xPR19MRVZFTD0yCmV4cG9ydCBQWVRIT05OT1VTRVJTSVRFPTEKZXhwb3J0IFBJUF9DQUNIRV9ESVI9IiRyb290L3BpcF9jYWNoZSIKZXhwb3J0IE1QTENPTkZJR0RJUj0iJHJvb3QvY2FjaGUvbWF0cGxvdGxpYiIKZXhwb3J0IFhER19DQUNIRV9IT01FPSIkcm9vdC9jYWNoZSIKdW5zZXQgUFlUSE9OUEFUSApta2RpciAtcCAiJHJvb3QvY2FjaGUiICIkcm9vdC9ydW5zIgpjZCAiJHJvb3QiCnRlc3QgLXggIiRyb290L3ZlbnYvYmluL3B5dGhvbiIKdGVzdCAtZiAiJHJvb3QvdmVudi9ydW50aW1lX3JlYWR5IgoiJHJvb3QvdmVudi9iaW4vcHl0aG9uIiAtdSAiJHJvb3QvY29kZS9zY3JpcHRzL3RyYWluX2dyYWljZV9sc3Rtbm9zaWYucHkiIC0tcm9vdCAiJHJvb3QiCg==' | base64 -d > "$new"
cd "$root"
out=$(sbatch "$new" 2>&1)
printf '%s
' "$out"
jid=$(printf '%s
' "$out" | awk '/^Submitted batch job [0-9]+$/ {print $4}')
test -n "$jid"
printf '%s
' "$jid" > "$root/job_id.txt"
printf '%s	%s	%s
' "$(date -u +%FT%TZ)" "$jid" 'v002 private-runtime install on login; same scientific code and configuration' >> "$root/submissions.tsv"
printf 'RUNTIME_INSTALL=COMPLETED
JOB_ID=%s
' "$jid"
