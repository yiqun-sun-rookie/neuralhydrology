# TEMPLATE — copy me to start a challenger

```bash
cp -r src/fair_benchmark/experiments/TEMPLATE src/fair_benchmark/experiments/001_my_idea
```

Then:
1. Edit `submission.yaml` (method name, family, attestation, mode).
2. Replace `predict.py` with your model. The only hard contract: read **only**
   the allowed bundle (`../../frozen/bundle/*`) and write `predictions.csv` with
   columns `basin,date,qsim` (mm/day) for all 531 basins over the eval window
   (1989-10-01 … 1999-09-30). Train however you like — any ML/AI method, any
   framework — as long as the inputs stay inside the budget.
3. Generate predictions, then score:

```bash
python src/fair_benchmark/experiments/001_my_idea/predict.py \
    --out src/fair_benchmark/experiments/001_my_idea/predictions.csv

python -m fair_benchmark.score \
    --predictions src/fair_benchmark/experiments/001_my_idea/predictions.csv \
    --experiment  001_my_idea --track track0_forcing_only \
    --experiment-dir src/fair_benchmark/experiments/001_my_idea
# add --allow-unconfirmed while the Track-0 spec is still confirmed: false
```

The provided `predict.py` is a **toy** (qsim = 0.3·PRCP, a rational-method
placeholder) — it runs end-to-end and emits a valid-shape submission so you can
verify the pipeline before plugging in a real model. It will score far below the
baseline; that is the point of a skeleton.
