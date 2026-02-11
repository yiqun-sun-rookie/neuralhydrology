# Analysis Scripts

This directory contains scripts for analyzing and comparing Mamba vs LSTM results.

## Scripts

### `analyze_results.py`

Main analysis script for comparing Mamba and LSTM performance.

**Usage**:
```bash
python src/mamba_camelsh/scripts/analyze_results.py \
    --mamba_results results/03_mamba_camelsh/camelsh_mamba_mini_benchmark \
    --lstm_results results/03_mamba_camelsh/camelsh_lstm_mini_benchmark_* \
    --output_dir results/03_mamba_camelsh/analysis
```

**Output**:
- `model_comparison.csv`: Summary comparison table
- `mamba_vs_lstm_scatter.png`: Scatter plots (NSE and KGE)
- `mamba_vs_lstm_boxplot.png`: Box plots for distribution comparison

**Requirements**:
```bash
pip install pandas numpy matplotlib seaborn scipy
```

## Future Scripts

Additional analysis scripts to be added:
- `analyze_long_sequence.py`: Analyze long sequence (3000+ hours) results
- `extreme_events_analysis.py`: Analyze flood peak capture capability
- `computational_efficiency.py`: Compare training time and memory usage
- `spatial_analysis.py`: Analyze spatial patterns in performance
