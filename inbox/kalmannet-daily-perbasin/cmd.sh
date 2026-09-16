#!/bin/bash
# kalmannet-daily-perbasin sequence=142: E1 measured item: KalmanNet epoch wall time with 4 concurrent tasks on hgpu4 (3 development epochs each)
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=142 purpose=e1_probe_gpu2_seq142"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/e1_probe_gpu2_seq142
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=494d0ce2182e937c792d90505f2d4c14e4a495879ab932ec05e1fb03c515e68c
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
H4sIAAAAAAAC/+1YbW/bNhDOZ/0KTm2AGJ1svVm2E2iAEquxF79BlttmxUDQEh2ptl5KSm2Ntv99
J8lpnLT70CHLDEzPB0s+HsnneLzjUc3WOqYZTlmypE2+yVl09OiQAZ12u3wCHj4NTddv3yu5omia
fITkoydAzjPCYPqj/yee/dLKOWstw7hF4w9oSXggPEN9azi6xhfW2B7N8dXEdrE1Gl5O7D527LHl
XgzwKw2rsmrIPcU4RVdkE5F4QjNEWIQywtfwwsj2DNFPGWUx2SDiRyHnYRKj5RZtSB57AWX4g9ZM
tyjkiNH3ecio3xSezc+LCZAkvUuWUkwiaq79NNUkqpSbVCr2655WSlgWZjCwGdykub7XEic+5aay
Lymo3Rd5ac6llDKpaDL3u98w6A1Dnu6rZyHwkeVTXT6V5T15aa4pS8qxeo+BVBhGc7o/Y+CHzGz5
JCNKK0gi2uJ5vA3ft9blKhbR6JNws8Ue2L7hGMhhcEsYY1XBPv1AN0ka0Tjbrb/chVXEZBPexNTH
jEYk84JvvmmxPC44t6hSxTgGi1TM6XtF32ea5FmaZwfBqlVmIenYwsekyTMfqO0RpYwl7CB5AjOB
QwhINEFpmNIV0BDyqAgGudMR6Kc0YRmaXbuD6aQ/nbivnaFrn1+79sW0b5vKrmU6c4fj4R+2Ke8E
k+libjtz0AWdi0XfgrC8GNi4P5xb5yMQ3o48Hc/wZDHG7sCxrf7c1NH4avRAMp3Zk/ORNX8ghn/2
m5lzX3o7bjFKJRxOLvHIurYd83KyKOXA7NXwwsYvpw78DieuPbojVPGfWe7gyfz1MWFrnhIPZmHe
6ZPPemu5O571h85h7NIsSpFrj2cHxOaQyLzpX+4CajAd24fByyNwOCIXYmpwQKyyhHmBEK3h9EJS
isTn1S4X4e3+IhaSO/Ki4CwmeNg3n59w6iMphtaTk/lo4Yyx5TjWNXat+RUooBdIaTRSER2EtdCI
Q583s09ZQ3hb0a4MEdGf6MsX9BlRL0iQ+BJKJTyZ4qqxLH7M5z8wTyyKoTBDXfUMfb1NFFf92Uzb
dTXvJqjE04U7W7h4Zjn2xDUPZVV4IdgxtN+4jgVmXs5NUZL2ppIyyrPitE4TL5A8Gm7C+AapolD1
m7uW49rFlgCjKHpxzBtnKFyhkxN0TwG2BOwVVZflRgP9hpROr93rGV1ZRg3okAU0rpxQqkNp+hKO
yj62FnDuwOF6jV8P4aR9fbvw+hlahULltdIpZTdUedrcLT6CqvPWf79PzwtJVdvd82nV0vqRn1GQ
8AwsKx5F9dpAxQUjozDDPdtE2APU+9Fmj8I49JLYJ1pRkvNWHOBVCDV0WaSn2yyAIlo6R1J+IJFC
eZIzj2Kg5xfl/EGwShk4mnrrJtxnjmr8LZqt8obCs+Y7nsT/zhzlJf/ujv/wqahq58H9X9aNTn3/
fwp8FpAIhxH1IENhyDpezhiNva14itRfd20sLINyRSKIXWgQf+rzgFgMs4bcUPQsA7WUpGS7SYiP
eUDUtgFtwAT0HnyMKvoQrbM0up7R7i5VqrfVlWyoXbL0Oka7rflLf7lcKYR6K7Jaar7RMxS/3e60
O0SBTecrXb+YDol7B3ox6EpZ9QxVk3ter7dsLzWZeAb1e35bNVZeTyMwDKUdQ9ZXXV2lalfXiUG6
suatKFEVTxYF9LU0I2dpwmkxpK2giBKeMyhzwoxG+99FyoMQfSSbDSpyFvoYZgHS0bcFz8rCgSNI
7eVnDHSiob2EWPXniEJl2CiXb2cOzPu2sO6nPFIpnFvz4QRDltXacKLCVQ6US42uqldL9s8HVfRu
R/5uUAH9WVAvHYu5x8K0dMV3Phe+1in7CfP/XWAc/Sf5X4YC72H+12S1zv9PgUdOHMIj54w6EdSo
UaNGjRo1atSoUaNGjRqPgL8AOVGWNwAoAAA=
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
