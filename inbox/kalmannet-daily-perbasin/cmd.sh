#!/bin/bash
# kalmannet-daily-perbasin sequence=139: E1 measured item: UKF per-update wall time on hcpu48 (single thread), KalmanNet CPU epoch time (information), Sobol reference timing
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=139 purpose=e1_probe_cpu_seq139"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/e1_probe_cpu_seq139
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=63a3ae409fab5e807f2dc70081f98245643fb7d12f0e91b426988b5a4d9b101f
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
H4sIAAAAAAAC/+1YbW/bNhDOZ/0K1k3RFqusV8t2AmNwYjXx4pfAVroFw0DQEhWplkSVlNIGS//7
jrKTOsGGrtucGZseGJEjHu+Op3t55KbG6YeSiqL5XrBsbyvQAY5tV1fA46vRtu+/r+4buu2095C+
9wQoRUE4mN/7f+JXBTXop5zyOKVZgUOSxslN4wA1Bv3h6BIf98fuaI7PJq6H+6PhycQd4Jk77nvH
p/idhU3ddPSu4TTegJplnAVyZ7kMccYCWt3MyU3CSIBFRMyWA8tgEDUKIpaiWXwqpLzutyyz7YQm
ta22Y3SMDiGGGXZsxzGt0PQDauhd3TBMX6e06y9sP7CCBQl127dbXbMt7ays5pwtaFMkJU+lYjMI
id9y4EP8ru4sKOkaVtAFlZ0QbrYce0E6rU5ITFPvmCYJrE5ghkQP9IVDu7reUNDn6gwlz5mgUqVr
oJQSUXIaoLig6QG6OHuLIHxqmQekoOgjSRJUQDARy1Dk56XdQa9EnF0lFBURpyR4/QadkSQl2YQW
6Pj8AtGc+dFqz6s4CxlPSRGzDOTmbMESxGlIOc18KmVAUxXX6pBY+DzOi7ugbx5fylRRhsWfZXwC
en37Tc8Uw8nwUX8+nGDDtO221dXx3AXZSqBj2rdwulvj1lrF/+/oh8drtTr69vTbutnW/2n9lcBX
A2TfmtsxACWxPsHagJDZcnsnCcn7i/JZ+Vr9N7X7Wtxaj/lK/9fb1qP+r7fbbb3u/0+B7bUFZXsd
QdleM1C22AeULbYA5WH1K3/2+Te1R5NjS/XfbrX+qP5btuE84n+G0bLq+n8KPH+mlYJrizjTaHaN
FkREynP0TUl6AFQHiE/EgOKsGY+kf4iXWQZ0Ba3Yj7piP8CboBRVwlP0kfEl5eIQ0U8F5RlJEAnS
WAjgPki+lMRAsprK8/mRNIhU9T1bqBlJaW8Z5LmlUqPKWhXyd0MoJ7yIJX3qrVzZWJJOiZ6xeaea
fQ9uwSahSj4nl3oP9kuG1tONA0s/0PUHetXqHaqkm3qiIOY9DTghMbSIpVQTZXYTf9CWFffLaIED
AlQb+3CiRGAwiSH4cYZNA0OfoAnLK0a+LvQOvrYwSeKrjAaYU6CIfnT/BDQItfROo8aqlDEcAwv6
wbC6Gz6xssjLYhec0qpWo7543xRFAG5tOEk5Z3znfASvFAF8XaUM5XFOQ3BBKVPIEQRkRYE3KMYL
dH7pnU4ng+nE+3E29NyjS889ng7cnrFemUwv5u5sDkuQc+s947MR9k5nbn8wnJzgUf/SnfVOJhfV
fRB+Nzx28dvpDP4OJ547+rJxpfK8750+WbRkxYqc+GCF+wdPbvXu5N74fDCc7USOFGmOPHd8vjvO
7JAvPw1OYIYcn7r4dDp2d8Itn/gRVdIlNGek5qixv8qlBnx76G1DoX7EUGMC9YvnXn/mIZg/vf35
6GI2xj9Mj/BwgCImit7+K3mRg+k1ktPjTgZe7ef43J1hrz8/Q5JlFDQA6epngu9eiNcNJYKBiNQM
WUijha8xAYMkoUTQQ5SB6/4huuI0R2pqoJcpTK8ESTMvkSYXNTAmfy5YC41p2r+GIJIFjOGVQEpT
KaD8TuBhIfZZFhBLjn2hZREOYxjBFRHIb4oIZrB6hNQS/Qu9pfpRQ2iPRFdElbGkmd/IaSxHN9qJ
VL97gb4fsZKFgOqd8A7WhPwfnEvYlQqJT/2C8ZudcA48EuDYmgkiRxK4VfL9tZxVuN/b/x4Y5Zfa
dScDIJgx1Cn3EcjHInpUhofVOoJ1Za9GjRo1atSoUaNGjRo1atSoUeM/h98AMDtG+gAoAAA=
KDPP3_PAYLOAD_BASE64
echo "$PAYLOAD_SHA256  $REQ/payload.tar.gz" | sha256sum -c - >/dev/null || { echo FAIL_PAYLOAD_SHA256; exit 85; }
tar --warning=no-timestamp -xzf "$REQ/payload.tar.gz" -C "$REQ" || { echo FAIL_EXTRACT; exit 86; }
echo "PAYLOAD_OK sha256=$PAYLOAD_SHA256 bytes=$(stat -c %s "$REQ/payload.tar.gz")"
cp "$ROOT/launcher/resource_bind.py" "$ROOT/launcher/precheck.sh" "$REQ/" || exit 89
sed -i 's/\r$//' "$REQ"/*.slurm "$REQ"/precheck.sh 2>/dev/null; true
echo "=== QOS_LIMITS (read-only) ==="
timeout 25s sacctmgr -n -P show qos qos_sunyiq format=Name,MaxJobsPU,MaxSubmitJobsPU,MaxTRESPU,GrpTRES,MaxWall,Priority,Preempt 2>&1
echo "=== HCPU48_IDLE (read-only) ==="
timeout 25s sinfo -p hcpu48 -h -t idle -o '%D idle nodes' 2>&1
"$PY" -I -B "$ROOT/launcher/launcher_v3.py" --request "$REQ" --policy "$ROOT/resource_policy_v3.json"
rc=$?; echo "LAUNCHER_EXIT=$rc"
for f in "$REQ"/submission_job*.receipt.json; do [ -f "$f" ] && { echo "RECEIPT_BEGIN $f"; cat "$f"; echo "RECEIPT_END"; }; done
exit $rc
