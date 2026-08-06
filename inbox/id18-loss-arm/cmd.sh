#!/bin/bash
echo "=== RUNNING JOBS (do not disturb) ==="
squeue -u "$USER" -o "%.10i %.14j %.10P %.9T %.11M %.6D %R" 2>&1 | head -20
echo "=== PARTITION IDLE ==="
sinfo -o "%.10P %.6a %.10l %.6D %.6t %N" 2>&1 | head -12
echo "=== REPO HEAD ==="
cd ~/neuralhydrology 2>/dev/null && git rev-parse --abbrev-ref HEAD && git log --oneline -1 && git status --short | wc -l
echo "=== CAMELS DATA ==="
du -sh ~/neuralhydrology/data/camels_us 2>&1 | head -2
ls ~/neuralhydrology/data/camels_us 2>&1 | head -8
echo "=== LOSS MECHANISM CODE ==="
ls ~/neuralhydrology/src/loss_mechanism_531/ 2>&1 | head -20
echo "=== E01 RESULTS PRESENT? ==="
ls ~/neuralhydrology/results/18_lstm_fair_531/ 2>&1 | head -12
echo "=== CPU PARTITION DETAIL ==="
sinfo -p hcpu48 -o "%.10P %.6D %.6t %.8c %N" 2>&1 | head -6
echo "=== DISK ==="
df -h /data1 2>&1 | tail -2
