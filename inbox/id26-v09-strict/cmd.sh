#!/bin/bash
# id26-v09-strict seq=5 : find the uploaded file wherever it landed. Read-only search.
export LC_ALL=C
WANT="feee746c7bda7970c8bac470969bf4247118f8f35d6cf543a44a8a6b4bd1bed7"

echo "=== A NEWEST THINGS IN \$HOME (top level, by mtime) ==="
ls -lat "$HOME" 2>/dev/null | head -20

echo "=== B ANY .tar.gz ANYWHERE UNDER \$HOME (depth<=5) ==="
find "$HOME" -maxdepth 5 -type f -name '*.tar.gz' 2>/dev/null | head -30

echo "=== C ANY FILE >40MB MODIFIED TODAY (depth<=5) ==="
find "$HOME" -maxdepth 5 -type f -size +40M -newermt '2026-08-07 00:00' 2>/dev/null \
  -printf '%TY-%Tm-%Td %TH:%TM  %10s  %p\n' 2>/dev/null | head -30

echo "=== D V09_STRICT TREE ==="
find "$HOME/v09_strict" -maxdepth 4 2>/dev/null | head -40

echo "=== E OTHER PLAUSIBLE LANDING SPOTS ==="
for d in /data1/home/$USER /data1/$USER /tmp /data1/tmp "$HOME/upload" "$HOME/uploads" "$HOME/data"; do
  [ -d "$d" ] && echo "-- $d --" && ls -lat "$d" 2>/dev/null | head -8
done

echo "=== F HASH-MATCH SCAN over today's >40MB files ==="
FOUND=""
for f in $(find "$HOME" -maxdepth 5 -type f -size +40M -newermt '2026-08-07 00:00' 2>/dev/null | head -20); do
  s=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)
  echo "  $s  $f"
  [ "$s" = "$WANT" ] && FOUND="$f"
done
[ -n "$FOUND" ] && echo "MATCH FOUND: $FOUND" || echo "NO HASH MATCH among scanned files"

echo "=== G DISK / QUOTA (did the upload maybe fail on space?) ==="
df -h /data1 2>&1 | tail -1

echo "=== END ==="
