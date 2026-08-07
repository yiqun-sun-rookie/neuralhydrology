#!/bin/bash
# a02 seq=5 : is the upload still growing, or did it stall/complete?
# local reference: 1068849391 bytes, sha256 202d83ff0af4a18ab70f0b263a102f8de10e6f7cf24515164e93b5c60bd44907
export LC_ALL=C
F=~/nature_1st_a02.tar.gz
EXPECT=1068849391

echo "=== A SIZE SAMPLES (30 s apart) ==="
for i in 1 2 3 4; do
  if [ -f "$F" ]; then
    S=$(stat -c%s "$F")
    printf "  t=%3ds  bytes=%s  (%.1f%% of expected)\n" $(( (i-1)*30 )) "$S" \
      "$(awk -v a=$S -v b=$EXPECT 'BEGIN{print 100*a/b}')"
  else
    echo "  t=$(( (i-1)*30 ))s  FILE MISSING"
  fi
  [ $i -lt 4 ] && sleep 30
done

echo "=== B VERDICT ==="
S=$(stat -c%s "$F" 2>/dev/null || echo 0)
if [ "$S" -eq "$EXPECT" ]; then
  echo "  SIZE MATCHES EXACTLY -- verifying sha256 (may take ~30 s)"
  echo "  local  : 202d83ff0af4a18ab70f0b263a102f8de10e6f7cf24515164e93b5c60bd44907"
  echo "  remote : $(sha256sum "$F" | cut -d' ' -f1)"
  echo "  tar readability:"
  tar -tzf "$F" 2>&1 | wc -l | sed 's/^/    entries: /'
else
  echo "  INCOMPLETE: have $S of $EXPECT bytes ($(awk -v a=$S -v b=$EXPECT 'BEGIN{printf "%.1f", 100*a/b}')%)"
  echo "  -> if the numbers in section A are still rising, the transfer is running; wait."
  echo "  -> if they are frozen, the transfer stalled and must be resumed or restarted."
fi

echo "=== C DISK / QUOTA SANITY ==="
df -h /data1 2>&1 | tail -1
