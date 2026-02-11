# Results Template

Use this template to record experimental results as they become available.

---

## Mini Benchmark Results

### Mamba Mini Benchmark
- **Experiment ID**: `camelsh_mamba_mini_benchmark`
- **Date**: [Date]
- **Config**: `src/mamba_camelsh/configs/camelsh_mini.yml`
- **Basins**: 50
- **Epochs**: 10
- **Sequence Length**: 168 hours (7 days)

#### Validation Results
- **Mean NSE**: [Value]
- **Median NSE**: [Value]
- **Mean KGE**: [Value]
- **Median KGE**: [Value]
- **Best Epoch**: [Epoch number]

#### Test Results
- **Mean NSE**: [Value]
- **Median NSE**: [Value]
- **Mean KGE**: [Value]
- **Median KGE**: [Value]

#### Training Metrics
- **Total Training Time**: [Hours]
- **Time per Epoch**: [Minutes]
- **GPU Memory Usage**: [GB]
- **Backend**: [mamba_ssm / transformers]

#### Notes
- [Any observations, issues, or notable patterns]

---

### LSTM Mini Benchmark
- **Experiment ID**: `camelsh_lstm_mini_benchmark`
- **Date**: [Date]
- **Config**: `src/mamba_camelsh/configs/camelsh_lstm_mini.yml`
- **Basins**: 50
- **Epochs**: 10
- **Sequence Length**: 168 hours (7 days)

#### Validation Results
- **Mean NSE**: [Value]
- **Median NSE**: [Value]
- **Mean KGE**: [Value]
- **Median KGE**: [Value]
- **Best Epoch**: [Epoch number]

#### Test Results
- **Mean NSE**: [Value]
- **Median NSE**: [Value]
- **Mean KGE**: [Value]
- **Median KGE**: [Value]

#### Training Metrics
- **Total Training Time**: [Hours]
- **Time per Epoch**: [Minutes]
- **GPU Memory Usage**: [GB]

#### Notes
- [Any observations, issues, or notable patterns]

---

## Full Training Results

### Mamba Full Training
- **Experiment ID**: `camelsh_mamba_full`
- **Date**: [Date]
- **Config**: `src/mamba_camelsh/configs/camelsh_full.yml`
- **Basins**: 455+
- **Epochs**: 30
- **Sequence Length**: 336 hours (14 days)

#### Validation Results
- **Mean NSE**: [Value]
- **Median NSE**: [Value]
- **Mean KGE**: [Value]
- **Median KGE**: [Value]
- **Best Epoch**: [Epoch number]

#### Test Results
- **Mean NSE**: [Value]
- **Median NSE**: [Value]
- **Mean KGE**: [Value]
- **Median KGE**: [Value]
- **NSE ≥ 0.7**: [Count] ([Percentage]%)
- **NSE < 0.5**: [Count] ([Percentage]%)

#### Training Metrics
- **Total Training Time**: [Days/Hours]
- **Time per Epoch**: [Hours]
- **GPU Memory Usage**: [GB]
- **Backend**: [mamba_ssm / transformers]

#### Per-Basin Performance
- **Top 10 Basins (by NSE)**: [List]
- **Bottom 10 Basins (by NSE)**: [List]

#### Notes
- [Any observations, issues, or notable patterns]

---

### LSTM Full Training
- **Experiment ID**: [ID if available]
- **Date**: [Date]
- **Config**: [Config path]
- **Basins**: 455+
- **Epochs**: 30
- **Sequence Length**: 336 hours (14 days)

#### Validation Results
- **Mean NSE**: [Value]
- **Median NSE**: [Value]
- **Mean KGE**: [Value]
- **Median KGE**: [Value]
- **Best Epoch**: [Epoch number]

#### Test Results
- **Mean NSE**: [Value]
- **Median NSE**: [Value]
- **Mean KGE**: [Value]
- **Median KGE**: [Value]
- **NSE ≥ 0.7**: [Count] ([Percentage]%)
- **NSE < 0.5**: [Count] ([Percentage]%)

#### Training Metrics
- **Total Training Time**: [Days/Hours]
- **Time per Epoch**: [Hours]
- **GPU Memory Usage**: [GB]

#### Notes
- [Any observations, issues, or notable patterns]

---

## Long Sequence Test Results

### Mamba Long Sequence
- **Experiment ID**: `camelsh_mamba_longseq`
- **Date**: [Date]
- **Config**: `src/mamba_camelsh/configs/camelsh_longseq.yml`
- **Basins**: 50
- **Epochs**: 10
- **Sequence Length**: 3000 hours (125 days)

#### Validation Results
- **Mean NSE**: [Value]
- **Median NSE**: [Value]
- **Mean KGE**: [Value]
- **Median KGE**: [Value]
- **Best Epoch**: [Epoch number]

#### Test Results
- **Mean NSE**: [Value]
- **Median NSE**: [Value]
- **Mean KGE**: [Value]
- **Median KGE**: [Value]

#### Training Metrics
- **Total Training Time**: [Days/Hours]
- **Time per Epoch**: [Hours]
- **GPU Memory Usage**: [GB]
- **Backend**: [mamba_ssm / transformers]

#### Comparison with seq_length=168
- **NSE Improvement**: [Value] ([Percentage]%)
- **KGE Improvement**: [Value] ([Percentage]%)
- **Memory Increase**: [Value] ([Percentage]%)
- **Time Increase**: [Value] ([Percentage]%)

#### Notes
- [Any observations, issues, or notable patterns]
- [OOM issues? Performance gains?]

---

## Comparison Summary

### Performance Comparison Table

| Metric | Mamba (Mini) | LSTM (Mini) | Mamba (Full) | LSTM (Full) | Mamba (Long-seq) |
|--------|--------------|-------------|--------------|-------------|------------------|
| Mean NSE (Test) | [Value] | [Value] | [Value] | [Value] | [Value] |
| Median NSE (Test) | [Value] | [Value] | [Value] | [Value] | [Value] |
| Mean KGE (Test) | [Value] | [Value] | [Value] | [Value] | [Value] |
| Training Time | [Value] | [Value] | [Value] | [Value] | [Value] |
| GPU Memory | [Value] | [Value] | [Value] | [Value] | [Value] |

### Statistical Significance

#### Paired t-test (Mamba vs LSTM, Mini)
- **NSE**: t = [Value], p = [Value], significant = [Yes/No]
- **KGE**: t = [Value], p = [Value], significant = [Yes/No]

#### Paired t-test (Mamba vs LSTM, Full)
- **NSE**: t = [Value], p = [Value], significant = [Yes/No]
- **KGE**: t = [Value], p = [Value], significant = [Yes/No]

---

## Key Findings

1. **Performance**: [Summary of performance comparison]
2. **Long Sequences**: [Summary of long sequence results]
3. **Efficiency**: [Summary of computational efficiency]
4. **Extreme Events**: [Summary of flood peak capture]

---

**Last Updated**: [Date]
**Status**: [In Progress / Complete]
