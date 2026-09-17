#!/bin/bash
# kalmannet-daily-perbasin sequence=154: diagnostic 2: exact zero-gain gate through the Phase A pool invocation path (development mode, 1 epoch)
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=154 purpose=zero_gain_probe2_seq154"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/zero_gain_probe2_seq154
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=b825034d57e136ea18ba6ea63eec13f4be4a357cc03a1ca36108e449666f7582
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
H4sIAAAAAAAC/+1abXPbuBH2Z/2KreI7x2koEiT15ozuRrZVW40teyT52kzbwUAkKDKWSIYgE/vi
/PcuKFqWXaU3d8f4OC0ez1jCCxeLFfbZxUoNPeEfMi7SxnsRhTvfBAaiZdv5K+Lpq2W11mOrfmLY
bWsHjJ1nQCZSluDyO/+f+FyD+oyJIBT1A/hHDaBuENtq4sdQf120bMNet0yjazYfWsQwu0anaFmG
3X14zjbM9kOr2TSszrrVIUa3vdHqGg8yu01itTtFi5ik3VyPEZt0mt11y7TxlHSNeg3+hR11fhPz
JFjyMKUeWwaLW9xQ/bg/PHtHj/rng7MJfTsaTGn/bHgyGhzT8eC8Pz06pT9Z1DTMltElLSm3fh2E
rnwyu/ZoGLk874zZ7SJiLhU+M5stHP4sNUiZuBaN9CaV85vejHvEnnGjM7Ndk/NZp9MxrLZnNV2n
OWvNjFl3xhybWcRjVpexlt2xO06rM2txbrbc1aZ+5klE5ywIaZxEM242xCJLllI+MU3b5MzseK12
t9Pq8jZ+MG135jXdjucR5rZcp0NmjsGYdKkuI2SGixC3S1yCq6OZvuRbyZI4ElyKdAM2DyORBg6Y
B8BvmJOCVECTCsCcpRxSP4myuY+vHC59Jjj0IY6iBQThx8hhaRCFELPUh5cu/8gXUSztD0u022sg
wOPI8fdzCyZZSAN3fch+1eeymnDYnwxH9P500skAJ+czOqa9Mt7vEZof8nKFFr5SstCVy5UrtPDc
coUWBFCu0IJHyhVa0FHZQnNWK1doQY6lCr3n2HKFFlRdsqYrxn8itOD/nCmpcJIgzgn5K1Ra+1Lb
UVijoa+j2Ddb4xfyP9NsPsn/jHZb5X/PAwzbdyUH4zsnzu7IHan9XtlbYnJJsreG5rJkb4vQJcne
GqhLkr01Xpcke2vYLkn21uhdmuwtQbwk2VtjeTmyt4f0kmRvjexl6b0twK9lq2j9LeL/9jyp7PiP
5/Er8Z+0CHla/8Grrqni/3PgxZ/0TCT6LAh1Hn6EGRN+7QX8Kg8+2CgabJYUQNPyusHWekGQCr7w
/kvZADhz/P1G7cXkUC6Iwt5HMy1kS967duPY0n6er87rxoyYJWkg1+j5yBl2Z2NIlnJEj2z25Inv
oy58SGgxTzQ51Hv0fBrgwoZxYDcPDOORXC0voGZ8U47vBklPd1nKiO5HS66LLLwNPujXbLFkYchT
6rJgcUsd3M5CUFyS5kU4ahK6YZHCxJhMfLQoWwTzkLs04UuWOv7a/HqShVK7/3BkKvgH0rQ39Iqy
NM7Sqiim50Sjffe+IVIXVdtQlCdJlFRST9SsJngKWgRxEHMPtahlSzwugJeWGr+JoySFy3fT04vR
8cVo+rfxcDo4fDcdHF0cD3qkGBldXE0G4wkO4fErnjl/e0anp+NB/3g4OqFn/XeDce9kdJX34+Sf
hkcD+peLMf4fjqaDs4cHVyIv+9PTZzPYpyi5FjFzcJXEOXj2Ve93Pj2/PB6OK3NM0mUM08H5ZbUU
qpg+fz8+wbhydDqgpxfng8qo5mCw4bXlNfI2aDHUd1dnq47vHmtcr3HHj6A+Qn+mk2l/PAWMS73d
ydnV+Jz+9eKQDo/BxwjY230pX2TA2geZY6TcxT5XVtX//J3Yr9ecCJWissz+ch8+Q4ij84THoC1g
7yGivs3NMULKcQPP44nYQ51IXX9VsBGYP+hoDj3MFgu4g08OPr//BuS6ohSJNyyZC9BCIpMDLuU+
mSC4C3tCb7wqsnhdfwNCz3P4xitd38MpaQJ7/wz3AP9Qt5UF0XgnA8wnJldnU9g18+8bqOTTLJGa
hxB5sGsdwG6+lfob+FKYvtfrwYSs0gpigaQF3ARgN07acqCWQRg4UegyS6Y4Qg996gUhW+RJT3yb
+piTaIegZfAH8GderhT6k6m6/PZJbrAR38rkQ2YqUBk3vi8YyoxrZb7favUiI5GJm0wAq7JDHBdU
ENRvEc015ATupFFyWxn9UKtCv/vDT6y1WxE6Purt/oi+8EAwldMc/ZdYm/5sFv5cuLPyZuXN5Xqz
WXFvNje9ee3MZvWd2ZTO+9iZLVhZGcIItOFrcD65sPaSwrXXuVa1doM8+tJxn5874Pvv4eL8ko6u
zotr4ASvi/Ly97jntzNidehQ/hbkvo8lyxUrYqcWuFDyd1EoeGMDWsqF5Lm8wKQ5PFgE4RxkHE39
hDNX5O/xgQA/ECfOKk5pFvxQNe/RV45fVHTwolBhBfGq83AZsapPtJYkVrLJs/Y9z96TbPFbzmpT
rP28FPsLSn1r4h0q7v1f5F67ctxrV5177a9xr1197rUl2ZLHBaiiWubnh3fFuF6UgAdBWLX79rq2
9wbcqDC7pmmw66HSKaoDWggW1PO2G4V8s8o5GB0DvwnSngFIb4HwnxQy3+SjYKjv5xUUFBQUFBQU
FBQUFBQUFBQUFBQUFBQUFBQUFBQUFP4g/BsgrXGmAFAAAA==
KDPP3_PAYLOAD_BASE64
echo "$PAYLOAD_SHA256  $REQ/payload.tar.gz" | sha256sum -c - >/dev/null || { echo FAIL_PAYLOAD_SHA256; exit 85; }
tar --warning=no-timestamp -xzf "$REQ/payload.tar.gz" -C "$REQ" || { echo FAIL_EXTRACT; exit 86; }
echo "PAYLOAD_OK sha256=$PAYLOAD_SHA256 bytes=$(stat -c %s "$REQ/payload.tar.gz")"
cp "$ROOT/launcher/resource_bind.py" "$ROOT/launcher/precheck.sh" "$REQ/" || exit 89
sed -i 's/\r$//' "$REQ"/*.slurm "$REQ"/precheck.sh 2>/dev/null; true
"$PY" -I -B "$ROOT/launcher/launcher_v3.py" --request "$REQ" --policy "$ROOT/resource_policy_v3.json"
rc=$?; echo "LAUNCHER_EXIT=$rc"
for f in "$REQ"/submission_job*.receipt.json; do [ -f "$f" ] && { echo "RECEIPT_BEGIN $f"; cat "$f"; echo "RECEIPT_END"; }; done
exit $rc
