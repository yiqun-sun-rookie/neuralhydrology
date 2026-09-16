#!/bin/bash
# kalmannet-daily-perbasin sequence=143: E1 measured item: UKF per-update wall time on hcpu48 (single thread), KalmanNet CPU epoch time (information), Sobol reference timing
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=143 purpose=e1_probe_cpu2_seq143"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/e1_probe_cpu2_seq143
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=442b88031583ecc114c1c9ffe1d895c95ed5e4a6a36d04db1abb730ff91a593c
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
H4sIAAAAAAAC/+1YbW/bNhDOZ/0K1k3RFqssUZItK4ExOLGaePFLYCvdgmEgKImOVOutpJQ2WPrf
d5Sd1gk2DN2WzNj0fLAM8nh3PPHuHqqtcfahYqJsvxd5tvco0AFdy6qfgIdPbHSMu//rcaxb3c4e
0veeAJUoKQfze/9P/KqgFvtUMB6nLCvJkqZxctM6QK3hYDS+JMeDiTtekLOp65HBeHQydYdk7k4G
3vEpeWcSQze6uoO7rTegZhVnoVxZrZYky0NWDxb0JslpSEREjU4XpsEgapVUrES7/FRKeZt1rVBn
ndDqOXjZcZyugw0nsA28pAYLbF+nQVfvhgbGfscPfJ0Zfk8Plib2ez6mvrSztlrw3GdtkVQ8lYo7
uNPtMexbgd61A91Z4oBRG/dM2+75uh36tm7qLHR6diegNKAONbuO44QMGz3btqyWgj7Xe6h4kQsm
VboYpYyKirMQxSVLD9DF2VsE4VOrIqQlQx9pkqASgonyDEVBUVk99ErE2VXCUBlxRsPXb9AZTVKa
TVmJjs8vECvyIFqveRVny5yntIzzDOQWuZ8niLMl4ywLmJQBTXVc600SEfC4KO+Cvr19KVNHGSZ/
lvEJ2fXtN71TAjsjR4PFaEp0Rzc7PV0nCxdka4GeYd3C7m7xrbmO/9/Rjw3Lsk1nW7+j441+DK/h
F+WzstfgEdDWvuTio9n4k/oPr7t7v/7rNqRfU/+fAo9XFpTHqwhNLfgH8/9B53ik/Lc7nT/K/45l
6g/4H8aW3eT/U+D5M60SXPPjTGPZNfKpiJTn6JvS9gCoDhCfKAeKs2E8kv4hXmUZ0BW0Zj/qmv0A
b4IsVylP0cecrxgXh4h9KhnPaIJomMZCAPdB8lISA8lqK88XR9IgUtX3ua9mNGX9VVgUpspwfWpV
OL9bQgXlZSzpU3/tytaUdEr08fZI3fvuDcEioUo+J6f699ZLhtbX8YGpH+j6Pb1qfYeq2LaeKIx5
XwNOSLEW5SnTRJXdxB+0Vc39MlaSkALVJgHsKBEETBIIfpwRAxOonCzJi5qRb2pfj1ybhCbxVcZC
whlQxCD68gY0CLX0TmN4ncoEtmEQwT5gy9xyKq/Koip3wiutLjbqi/dtUYbg15aXjPOc756T4JYi
gLKrLEdFXLAl+KBUKRwTBHxFgUtUzkt0fumdzqbD2dT7cT7y3KNLzz2eDd0+3sxMZxcLd76AKTh2
mzWTszHxTufuYDianpDx4NKd90+mF/U4CL8bHbvk7WwOv6Op546/LlyrPB94p08WLpm0oqABWOHB
wZNbvdu5Nzkfjua7cUjKtECeOznfIW92yZmfhifQSY5PXXI6m7i74VdAg4gp6QpqNFIL1Npfn6cW
/LvvbkthQZSj1hRymCy8wdxD0Ib6+4vxxXxCfpgdkdEQRbko+/uv5EP2p9dINpE7GbjhL8i5Oyfe
YHGGJNkoWQjS9deC716I1y0lgr6I1AyZSGNloOUC+knCqGCHKAPfg0N0xVmB1BSjlyk0sQRJMy+R
Jic1MCa/GmyEJiwdXEMUqQ/deC2QslQKKL8TeZiIgzwLqSm7v9CyiCxj6MQ1HyhuyghasXqE1Ar9
C/Wl/rYhtAeia76a50m7uJFNWXZwtBuH/e4i/aXTSjYCunfDPZgUcgC8S/IrFY4+C8qc3+yGd+CS
AM82nBAZksqtz99fO7YKD/r73wO3/Jq+7nQIVDOGVOUBAvlYRA8y8bCeRzDf3DAbNGjQoEGDBg0a
NGjQoEGDBv8Z/AaYvZldACgAAA==
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
