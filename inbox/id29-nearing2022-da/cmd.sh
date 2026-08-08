#!/bin/bash
# ID29 seq=3: stage the reproduction package and fetch the extended forcings.
# Login-node work is limited to unpacking and downloading. No computation, no sbatch here.
set -o pipefail
export LC_ALL=C

ROOT=/data1/home/$USER/nearing2022_da
SRC=/data1/home/$USER/neuralhydrology_backup_20260304/data/camels_us
MB=/data1/home/$USER/hpc_mailbox

echo "=== A: stage code ==="
mkdir -p "$ROOT"
tar -xzf "$MB/inbox/id29-nearing2022-da/payload.tar.gz" -C "$ROOT" || echo "UNTAR FAILED"
echo "  package files: $(find $ROOT/neuralhydrology -name '*.py' | wc -l)"
echo "  configs: $(ls $ROOT/src/29_nearing2022_da_ar/configs 2>/dev/null | tr '\n' ' ')"
echo "  assimilation.py present: $([ -f $ROOT/neuralhydrology/evaluation/assimilation.py ] && echo yes || echo NO)"

echo "=== B: build data dir (symlink the shared CAMELS, keep extended local) ==="
mkdir -p "$ROOT/data/camels_us/basin_mean_forcing"
for d in camels_attributes_v2.0 usgs_streamflow; do
  [ -e "$ROOT/data/camels_us/$d" ] || ln -s "$SRC/$d" "$ROOT/data/camels_us/$d"
done
for p in daymet maurer nldas; do
  [ -e "$ROOT/data/camels_us/basin_mean_forcing/$p" ] || ln -s "$SRC/basin_mean_forcing/$p" "$ROOT/data/camels_us/basin_mean_forcing/$p"
done
ls -l "$ROOT/data/camels_us" | head -5
ls -l "$ROOT/data/camels_us/basin_mean_forcing" | head -8

echo "=== C: download extended forcings from HydroShare ==="
cd "$ROOT" || exit 1
mkdir -p dl
for pair in "maurer:17c896843cf940339c3c3496d0c1c077" "nldas:0a68bfd7ddf642a8be9041d60f40868c"; do
  name=${pair%%:*}; rid=${pair##*:}
  if [ -s "dl/${name}_extended.zip" ]; then
    echo "  ${name}: already downloaded ($(du -h dl/${name}_extended.zip | cut -f1))"
    continue
  fi
  code=$(curl -sL --max-time 600 -w '%{http_code}' \
      "https://www.hydroshare.org/django_irods/rest_download/bags/${rid}.zip" \
      -o "dl/${name}_extended.zip")
  echo "  ${name}: http=$code size=$(du -h dl/${name}_extended.zip 2>/dev/null | cut -f1)"
done

echo "=== D: unpack extended forcings ==="
cd "$ROOT/dl" || exit 1
FDIR="$ROOT/data/camels_us/basin_mean_forcing"

# maurer bag -> inner zip
if [ ! -d "$FDIR/maurer_extended" ]; then
  unzip -o -q maurer_extended.zip -d maurer_bag && \
  unzip -o -q maurer_bag/*/data/contents/maurer_extended.zip -d "$FDIR" && \
  echo "  maurer_extended: $(ls $FDIR/maurer_extended/*/*.txt 2>/dev/null | wc -l) files"
else
  echo "  maurer_extended already present"
fi

# nldas bag -> inner tar.xz
if [ ! -d "$FDIR/nldas_extended" ]; then
  unzip -o -q nldas_extended.zip -d nldas_bag && \
  tar -xJf nldas_bag/*/data/contents/nldas_extended.tar.xz -C "$FDIR" && \
  echo "  nldas_extended: $(ls $FDIR/nldas_extended/*/*.txt 2>/dev/null | wc -l) files"
else
  echo "  nldas_extended already present"
fi

echo "=== E: verify real Tmin/Tmax (the whole reason we need these) ==="
for p in maurer maurer_extended nldas nldas_extended daymet; do
  f=$(ls $FDIR/$p/*/01013500*.txt 2>/dev/null | head -1)
  [ -z "$f" ] && { echo "  $p: NO FILE"; continue; }
  awk -v prod="$p" 'NR>4 {n++; if ($9==$10) eq++; d+=$9-$10} END {printf "  %-16s n=%d  Tmax==Tmin=%.0f%%  mean diurnal=%.2fC\n", prod, n, 100*eq/n, d/n}' "$f"
done

echo "=== F: disk used ==="
du -sh "$ROOT" 2>/dev/null | tail -1
rm -rf "$ROOT/dl/maurer_bag" "$ROOT/dl/nldas_bag"
