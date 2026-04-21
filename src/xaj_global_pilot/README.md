# `xaj_global_pilot`

Current active workflow for Idea 10 is the conceptual benchmark pipeline under `CAMELS-US`.

Use these entrypoints:

- `python -m src.xaj_global_pilot.scripts.run_conceptual_screening`
- `python -m src.xaj_global_pilot.scripts.summarize_conceptual_benchmark`
- `python -m src.xaj_global_pilot.hpc.build_conceptual_benchmark_chunks --allow-scale-up`
- `python -m src.xaj_global_pilot.hpc.preflight_conceptual_benchmark_run`
- `python -m src.xaj_global_pilot.hpc.run_conceptual_benchmark_chunk`
- `python -m src.xaj_global_pilot.hpc.summarize_conceptual_benchmark_run`
- `src/xaj_global_pilot/scripts/run_conceptual_screening.py`
- `src/xaj_global_pilot/scripts/summarize_conceptual_benchmark.py`
- `src/xaj_global_pilot/hpc/`
- `src/xaj_global_pilot/configs/conceptual_benchmark_15_basins.csv`
- `src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531.txt`

Current benchmark scope:

- primary models: `xaj_pdd`, `hbv`, `gr4j_pdd`
- ablations only: `xaj`, `gr4j`
- scale-up target: `CAMELS-US` first
- `Caravan` is reserved for later external validation, not the first-pass benchmark

Recommended 531 workflow:

1. build chunks
2. run `preflight` on the formal chunk set
3. launch chunk jobs with `--skip-existing` enabled for resumability
4. run `summarize_conceptual_benchmark_run` after chunk completion

Legacy Caravan-oriented pilot utilities were copied to `archive_legacy/` and the old script names now redirect here on purpose.
