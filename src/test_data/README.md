# test_data

Shared lightweight test datasets and smoke-test configurations.

## Structure

- `configs/` — minimal training configs for quick validation
  - `quick_test.yml` — fast smoke test
  - `test_config.yml` — basic validation config
  - `test_*_basins.txt` — small basin lists for testing
- `scripts/` — data preparation utilities
  - `create_test_data.py` — generate test datasets from full data
  - `setup_test_environment.py` — set up test environment
  - `restore_demo_data.py` — restore demo data from backup
  - `prepare_new_region_data.py` — prepare data for new regions

## Quick Test

```bash
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/quick_test.yml --gpu -1
```
