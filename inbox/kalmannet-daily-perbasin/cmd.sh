#!/bin/bash
# kalmannet-daily-perbasin sequence=138: E1 measured item: KalmanNet epoch wall time with 4 concurrent tasks on hgpu4 (3 development epochs each)
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=138 purpose=e1_probe_gpu_seq138"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/e1_probe_gpu_seq138
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=9ea1eb4aae7a9e419e7507f2a2d9550113af264c43c83018151e0d32893047ea
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
H4sIAAAAAAAC/+1YbW/bNhDOZ/0KTm2AGJ1s6sW2lEADlFhNvPgNttw2KwqCluhYtS2ppNTWaPvf
d5Kcxkk7YB2yzMV0H2zpSB6f471S9cYyYilJeDxjdbHK+PrgwQkDtZvN4h/o/n9L178+l3xV1TX9
AOGDR6BMpJTD9gf/T3rySyMTvDELowaL3qMZFQvpCeo43d4VOXP6bm9CLgeuR5xe93zgdsjY7Tve
2QV5oRMNay1sqa1jdElXaxoNWIooX6OUiiU8cLo5QexjynhEV4gG61CIMI7QbINWNIv8BePkvV5P
NigUiLN3WchZUJeeTE7zDZCivI1nSkTXzF4GSaIrTC2cVMn9dWdWQnkapiDYXlwnmbEzEsUBE7a6
y8mh3WX5SSaUhHElH7J3l19zWA0ij3enpyHgwfjYwMcY7/ALdW2s6Id3ESi5YixjuzsugpDbjYCm
VG0s4jVriCzahO8ay+IU82gMaLjaEB90XwkC4AiYJYyIppKAvWerOFmzKN2ePzbhFAldhdcRCwhn
a5r6i6+2afAsyjE3mFrGOAGNiGDvVN3cwRRnaZKl+wCqUeQg5dAhh7Qu0gCQ7eBknMd8H2ECMEmA
/yssRkmYsDmgkLJ1Hgm43ZbYxyTmKRpdeRfDQWc48F6Ou557euW5Z8OOa6vbkeHI6/a7f7g23jIG
w+nEHU9gLsw5m3YciMmzC5d0uhPntAfMG8nD/ogMpn3iXYxdpzOxDdS/7N3jDEfu4LTnTO6x4c19
NRrf5d7IzaWUzO7gnPScK3dsnw+mBR+QveieueT5cAy/3YHn9m4BlfhHjnfxaOb6EPOlSKgPu3D/
+NF3vdHc64863fFeOGm6TpDn9kf7A2aPsLzqnG+j6WLYd/cClk+hKiIP4ulif0ClMfcX0noJVQsp
CZKflg4uw9PdI8w5t9hlaTwdkG7HfnokWICUCEaPjia96bhPnPHYuSKeM7mECegZUmu1REb7oCyM
kTAQ9fRjWpNel6hLPWT0Bn3+jD4h5i9iJD+HDokMhqQcLHoe++l3tJPzHihMkamdoC83KeKyMxrp
26X27QYlezj1RlOPjJyxO/DsPTkUkb9vAbqvvLEDWp5PbFlRdnZSUibSvEonsb9QfBauwuga6bJU
rpt4zthzc4cAnRh6dihqJyico6MjdGcCOAR4imZgXKuh35DatpqW1TIxRjVYkC5YVNqgmA4N6XOo
kR3iTKHgQFW9Ii+7UGJf3py7cYLmoVQarbBJsQyVhra3Z4+g17wx3+/D05xTdnR3TFqONL5nZrSI
RQqa5X95z1pD+bUiZbDDHd1kcAHmf8/V12EU+nEUUD1vxEUjWpB5CJ1z0Zonm3QBrbNyipRsP+KE
iTjjPiOALsh7+H0AlXAwM/OXdbjDHFT0t6jeKG4oIq2/FXH07+xRXPIN46/u/2oTq/fu/9hoadX9
/zHok4RkqErMh1xFIP/4Gecs8jfyMTJ+3Y7xsIjPOV1DGMOA/EOfB+RczBLSRL6yiNmCk9DNKqYB
EQuqNVswBkhg3r2PUfkaFdOZOtPpzNQNy9BbWpuaszZjs8D3zbnZMlTLNwyz3Wy2Lcucz+DCNads
3mobqq9psyDfDsk7lT0XqoFMi6ogoI1NvT0zLZM1NWpYM6zRJoVOrBUE1DLgpWmZKtZ93TR1zZq3
fEtvUiZL6EuhRsaTWLBcpKuiNaMi49DuhClb734XKUoi+kBXK5SnL/QhTBfIQF8PPC06CIEgyRef
MdCRjnZyY7leIAYNYq04vq06sO/rXLsfskg54dSZdAdE1QyjrVsYbnMwuZhhakZ5ZP9YKNbUtgn1
+2GFGlhr44cWamG9aX4jVEJv8kMuXJAIn4dJ4TTfeKf0Rfr58/9tYBz8J/kfN/H9779Yh5JQ5f9H
oAdOHNID5wzpgdOF9MCZouozK6qooooqqqiiiiqqqKKKKvop6E8a85fmACgAAA==
KDPP3_PAYLOAD_BASE64
echo "$PAYLOAD_SHA256  $REQ/payload.tar.gz" | sha256sum -c - >/dev/null || { echo FAIL_PAYLOAD_SHA256; exit 85; }
tar --warning=no-timestamp -xzf "$REQ/payload.tar.gz" -C "$REQ" || { echo FAIL_EXTRACT; exit 86; }
echo "PAYLOAD_OK sha256=$PAYLOAD_SHA256 bytes=$(stat -c %s "$REQ/payload.tar.gz")"
cp "$ROOT/launcher/resource_bind.py" "$ROOT/launcher/precheck.sh" "$REQ/" || exit 89
sed -i 's/\r$//' "$REQ"/*.slurm "$REQ"/precheck.sh 2>/dev/null; true
echo "=== HGPU4_GRES_USED (read-only) ==="
timeout 25s sinfo -p hgpu4 -N -O nodelist,gres:14,gresused:24,cpusstate 2>&1
echo "=== QOS_LIMITS (read-only) ==="
timeout 25s sacctmgr -n -P show qos qos_sunyiq format=Name,MaxJobsPU,MaxSubmitPU,MaxTRESPU,GrpTRES,MaxWall,Priority,Preempt 2>&1
"$PY" -I -B "$ROOT/launcher/launcher_v3.py" --request "$REQ" --policy "$ROOT/resource_policy_v3.json"
rc=$?; echo "LAUNCHER_EXIT=$rc"
for f in "$REQ"/submission_job*.receipt.json; do [ -f "$f" ] && { echo "RECEIPT_BEGIN $f"; cat "$f"; echo "RECEIPT_END"; }; done
exit $rc
