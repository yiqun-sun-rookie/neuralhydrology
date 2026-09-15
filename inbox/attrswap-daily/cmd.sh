#!/bin/bash
# seq=80 READ-ONLY gap-closer after the 2026-09-15 independent audit of seq=79 (P1 F1-F7, P3, P5):
# list the 7 smoke dirs by name, ctime scan of all four roots (no -type f), sacct since handoff by WorkDir,
# expanded queue with WorkDir, three shadow links, runs/ name digest, positive control, nh_final versions by metadata.
# Nothing is written or modified. No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
date "+epoch %s"
R2=/data1/home/sunyiq/precip_swap2_daily_2026_09
RA=/data1/home/sunyiq/attr_swap_daily_2026_09
RF=/data1/home/sunyiq/forcing_swap_daily_2026_09
RP=/data1/home/sunyiq/precip_swap_daily_2026_09
SH="$R2/data_shadow/camels_us"

echo "=== A. QUEUE expanded (-r splits arrays) with WorkDir; expect no WorkDir under the four roots ==="
squeue -u "$USER" -r -o '%.10i %.40j %.9T %.9P %Z' 2>&1 | head -40
echo "  squeue rc=${PIPESTATUS[0]}"
echo "  rows(excl header)=$(squeue -u "$USER" -r -h 2>/dev/null | wc -l)  rows_under_four_roots=$(squeue -u "$USER" -r -h -o '%Z' 2>/dev/null | grep -cE 'attr_swap_daily_2026_09|forcing_swap_daily_2026_09|precip_swap_daily_2026_09|precip_swap2_daily_2026_09')"

echo "=== B. sacct: every job of this account started since 2026-09-13T18:20 (expect 0 with WorkDir under the four roots) ==="
sacct -u "$USER" -S 2026-09-13T18:20 -X -n -P --format=JobID,JobName%40,State,Start,WorkDir%90 2>&1 | head -60
echo "  sacct rc=${PIPESTATUS[0]}"
echo "  total_since=$(sacct -u "$USER" -S 2026-09-13T18:20 -X -n -P --format=JobID 2>/dev/null | wc -l)  under_four_roots=$(sacct -u "$USER" -S 2026-09-13T18:20 -X -n -P --format=WorkDir%90 2>/dev/null | grep -cE 'attr_swap_daily_2026_09|forcing_swap_daily_2026_09|precip_swap_daily_2026_09|precip_swap2_daily_2026_09')"
echo "  -- gate jobs requeue check (sacct -D shows duplicates if any; expect 7 rows) --"
sacct -D -X -n -P -j 225205,225214,225218,225222,225226,225230,225234 --format=JobID,JobName%30,State,Start,End 2>&1
echo "  sacct -D rc=${PIPESTATUS[0]}"

echo "=== C. runs_smoke listing (expect 7 dirs: daymet_1248 imerg_refday_1249 imerg_uncal_refday_1249 imerg_utc_1251 gsmap_refday_1252 era5l_refday_1252 chirps_1254) ==="
ls -la --time-style=full-iso "$R2/runs_smoke" 2>&1
echo "  dir mtime/ctime: $(stat -c '%y | %z' "$R2/runs_smoke" 2>&1)"
echo "  runs/ dir      : $(stat -c '%y | %z' "$R2/runs" 2>&1)"
echo "  logs/ dir      : $(stat -c '%y | %z' "$R2/logs" 2>&1)"

echo "=== D. ctime scan, no type filter, per-root anchors; prints paths (expect 0 lines for each root) ==="
for pair in "$RA|2026-09-06 12:00" "$RF|2026-09-10 02:00" "$RP|2026-09-11 17:20" "$R2|2026-09-13 16:06"; do
  root="${pair%%|*}"; anchor="${pair##*|}"
  n=$(find "$root" -newerct "$anchor" 2>&1 | wc -l)
  echo "  $root  anchor=$anchor  entries_newer_ctime=$n"
  find "$root" -newerct "$anchor" 2>&1 | head -20 | sed 's/^/      /'
done
echo "  -- positive control: files in $R2/logs with mtime after 2026-09-12 12:00 (expect >= 14) --"
find "$R2/logs" -type f -newermt '2026-09-12 12:00' 2>&1 | wc -l
echo "  find rc=${PIPESTATUS[0]}"

echo "=== E. shadow links (three) and runs/ name digest (expect c5761df101fefe2a) ==="
for l in basin_mean_forcing/daymet usgs_streamflow camels_attributes_v2.0; do
  echo "  $l -> $(readlink "$SH/$l" 2>&1)"
done
echo "  dangling under shadow (xtype l): $(find -L "$SH" -maxdepth 3 -type l 2>/dev/null | wc -l)"
echo "  runs/ names digest: $(ls "$R2/runs" | sort | sha256sum | cut -c1-16)"
echo "  runs/ dirs=$(find "$R2/runs" -mindepth 1 -maxdepth 1 -type d | wc -l) runs_smoke dirs=$(find "$R2/runs_smoke" -mindepth 1 -maxdepth 1 -type d | wc -l)"

echo "=== F. nh_final versions by package metadata (no import) ==="
PY="$HOME/miniconda3/envs/nh_final/bin/python"
[ -x "$PY" ] && "$PY" -c "import importlib.metadata as m; print('  torch', m.version('torch'), 'numpy', m.version('numpy'), 'pandas', m.version('pandas'))" 2>&1 || echo "  nh_final python not found at $PY"

echo "=== G. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
