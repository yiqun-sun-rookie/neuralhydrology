#!/bin/bash
echo "=== A. CAMELS archive present? ==="
ls -d ~/neuralhydrology/data/camels_us 2>&1 | head -2
echo "forcing maurer files:"; find ~/neuralhydrology/data/camels_us/basin_mean_forcing/maurer -name "*_forcing_leap.txt" 2>/dev/null | wc -l
echo "streamflow files:";    find ~/neuralhydrology/data/camels_us/usgs_streamflow -name "*_streamflow_qc.txt" 2>/dev/null | wc -l
echo "=== B. static table + basin list ==="
ls -l ~/neuralhydrology/src/fair_benchmark/frozen/bundle/track0_statics.csv 2>&1 | head -2
ls -l ~/neuralhydrology/examples/06-Finetuning/531_basin_list.txt 2>&1 | head -2
echo "=== C. is unified_autoresearch already there? ==="
ls -d ~/neuralhydrology/src/unified_autoresearch 2>&1 | head -2
echo "=== D. repo git state (READ ONLY) ==="
cd ~/neuralhydrology 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>&1 && git log -1 --format="%h %s" 2>&1 && echo "dirty files:" && git status --porcelain 2>/dev/null | wc -l
echo "=== E. conda env ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null && conda activate nh_final 2>&1 && python -V 2>&1 && python -c "import pandas,pyarrow,numpy,psutil;print('pandas',pandas.__version__,'pyarrow',pyarrow.__version__,'numpy',numpy.__version__,'psutil',psutil.__version__)" 2>&1
echo "=== F. capacity ==="
df -h /data1 2>&1 | tail -2
echo "=== G. partitions ==="
sinfo -o "%.12P %.6D %.14F %.10m" 2>&1 | head -8
