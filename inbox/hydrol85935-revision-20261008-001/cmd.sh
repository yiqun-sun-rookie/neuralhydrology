#!/usr/bin/env bash
set -eo pipefail
date -Is
DATA=/data1/home/sunyiq/neuralhydrology/data/camels_us
for rel in basin_mean_forcing/maurer/03/02108000_lump_maurer_forcing_leap.txt basin_mean_forcing/maurer/09/05120500_lump_maurer_forcing_leap.txt basin_mean_forcing/maurer/15/09492400_lump_maurer_forcing_leap.txt; do
  printf '=== %s ===\n' "$rel"
  sha256sum "$DATA/$rel"
  wc -c -l "$DATA/$rel"
  head -n 8 "$DATA/$rel"
  tail -n 3 "$DATA/$rel"
done
printf '=== dependency support ===\n'
sbatch --help | sed -n '/kill-on-invalid-dep/p'
