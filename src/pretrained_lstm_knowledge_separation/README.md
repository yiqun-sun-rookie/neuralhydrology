# Pretrained LSTM Knowledge Separation

Do transferable knowledge and domain-specific knowledge exhibit partially separable
structure in large-sample pretrained hydrological LSTMs?

## Source Model

One CudaLSTM pretrained on CAMELS-US (531 basins, Kratzert 2019 split).
Existing checkpoint in `results/05_full_531_basins/`.

## Adaptation Groups

| Group | `finetune_modules` |
|---|---|
| head-only | `[head]` |
| embedding-only | `[embedding_net]` |
| lstm-only | `[lstm]` |
| full FT | `[embedding_net, lstm, head]` |

## Target Shift Conditions

Basin selection by Mahalanobis distance in standardized attribute space
(aridity, frac_snow, elevation, soil depth, etc.):

- **low shift** — basins close to source distribution center
- **high shift** — basins far from source distribution center

## Hypotheses

1. Low shift: head-only recovers most target benefit (knowledge already transferable)
2. High shift: deeper adaptation required (domain-specific info in deeper modules)
3. Deeper adaptation → more source-knowledge forgetting

## Prerequisites

- CAMELS-US dataset in `data/camels_us/full/` with attributes v2.0
- 531 basin list: `examples/06-Finetuning/531_basin_list.txt`
- Pretrained source model checkpoint (or train one with `source_pretrain.yml`)

## Workflow

### 1. Generate shift splits

```bash
python src/pretrained_lstm_knowledge_separation/scripts/build_shift_splits.py \
  --data-dir data/camels_us/full \
  --source-basin-file examples/06-Finetuning/531_basin_list.txt \
  --n-per-group 50
```

Output: `data/low_shift_basins.txt`, `data/high_shift_basins.txt`, `data/shift_summary.csv`

### 2. (Optional) Train source model

Skip if reusing an existing checkpoint.

```bash
python -m neuralhydrology.nh_run train \
  --config-file src/pretrained_lstm_knowledge_separation/configs/source_pretrain.yml \
  --gpu 0
```

### 3. Materialize adaptation matrix

```bash
python src/pretrained_lstm_knowledge_separation/scripts/run_matrix.py \
  --source-run-dir <path-to-source-run> \
  --output-dir results/pretrained_lstm_knowledge_separation
```

Output: 8 materialized configs + `manifest.json` with finetune commands.

### 4. Run adaptation experiments

Execute the 8 finetune commands printed by step 3:

```bash
python -m neuralhydrology.nh_run finetune --config-file <materialized_config> --gpu 0
```

### 5. Summarize results

```bash
python src/pretrained_lstm_knowledge_separation/scripts/summarize_results.py \
  --results-csv <collected-results.csv> \
  --output-dir results/pretrained_lstm_knowledge_separation
```

Output: `summary_table.csv`, `summary.md`

### 6. Analyze representation drift

```bash
python src/pretrained_lstm_knowledge_separation/scripts/analyze_representations.py \
  --source-acts <source-activations-dir> \
  --adapted-acts <adapted-activations-dir> \
  --output-dir results/pretrained_lstm_knowledge_separation
```

Output: `drift_metrics.json`

## Expected Artifacts

```
results/pretrained_lstm_knowledge_separation/
  manifest.json              # 8 adaptation run specs
  summary_table.csv          # mean NSE + gain/loss per group × shift
  summary.md                 # human-readable summary
  drift_metrics.json         # cosine distance + CKA per module
data/
  low_shift_basins.txt       # target basins (close to source)
  high_shift_basins.txt      # target basins (far from source)
  shift_summary.csv          # per-basin distance scores
```

## Tests

```bash
pytest test/test_pretrained_lstm_knowledge_separation_splits.py \
       test/test_pretrained_lstm_knowledge_separation_configs.py \
       test/test_pretrained_lstm_knowledge_separation_runner.py \
       test/test_pretrained_lstm_knowledge_separation_summary.py \
       test/test_pretrained_lstm_knowledge_separation_representations.py -v
```
