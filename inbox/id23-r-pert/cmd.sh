#!/bin/bash
# id23-r-pert seq=4 : READ-ONLY G0 failure forensics. No job submission, no compute.
set -o pipefail
DEST=/data1/home/$USER/id23_r_perturbation
source /data1/home/$USER/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$DEST"
export PYTHONPATH="$DEST/src:$DEST/vendor:$PYTHONPATH"

echo "=== BLAS / LAPACK BUILD ==="
python -c "
import numpy as np
print('numpy', np.__version__)
try:
    cfg = np.show_config('dicts')
    for k, v in cfg.get('Build Dependencies', {}).items():
        if k in ('blas', 'lapack'):
            print(k, v.get('name'), v.get('version'))
except Exception as e:
    print('show_config dicts unavailable:', e); np.show_config()
"
echo "=== PER-BASIN DIFF DISTRIBUTION ==="
python -c "
import pandas as pd, numpy as np
f = pd.read_csv('results/23_camels_switch_confirmation/noise_axis_r_perturbation_hpc/a0_parity_per_basin.csv')
d = f['max_abs_forecast_diff']
print('n', len(f))
print('max|diff| quantiles:')
for q in (0.0,0.25,0.5,0.75,0.9,1.0):
    print(f'  q{q:.2f} {d.quantile(q):.3e}')
print('within 1e-9 :', int((d<=1e-9).sum()))
print('within 1e-6 :', int((d<=1e-6).sum()))
print('within 1e-3 :', int((d<=1e-3).sum()))
print('bitwise days: median', int(f['n_days_bitwise_identical'].median()), 'of 1260')
print()
print('NSE impact (this is what the degraded gate cares about):')
n = f['nse_abs_diff']
print('  max ', f'{n.max():.3e}', ' median ', f'{n.median():.3e}')
print('  basins with |dNSE| > 1e-4 :', int((n>1e-4).sum()))
print('  basins with |dNSE| > 1e-3 :', int((n>1e-3).sum()))
print()
print('posterior deviation max:', f['posterior_max_deviation'].max())
print()
print('worst 5 by max|diff|:')
print(f.nlargest(5,'max_abs_forecast_diff')[['basin_id','max_abs_forecast_diff','nse_abs_diff','n_days_bitwise_identical']].to_string(index=False))
print()
print('calibration on HPC (compare to local: mean-z2 median 187.2, terciles 6.7/32.4/525):')
print('  z2_mean median   ', round(f['z2_mean'].median(),3))
print('  z2_median median ', round(f['z2_median'].median(),4))
print('  terciles         ', round(f['z2_mean_low'].median(),2), round(f['z2_mean_mid'].median(),2), round(f['z2_mean_high'].median(),2))
print('  |err|/sigma      ', round(f['abs_error_median_over_sigma'].median(),4))
"
echo "=== IS numpy 1.26 AVAILABLE IN ANY ENV? ==="
for e in nh_final nh_clean neuralhydrology knet_clean; do
  V=$(conda run -n $e python -c "import numpy;print(numpy.__version__)" 2>/dev/null | tail -1)
  echo "  $e : ${V:-unavailable}"
done
echo "=== NO JOBS SUBMITTED THIS ROUND ==="
squeue -u $USER -o "%.10i %.14j %.9P %.8T" 2>&1 | grep -i r_pert || echo "  no r_pert_* jobs in queue"
