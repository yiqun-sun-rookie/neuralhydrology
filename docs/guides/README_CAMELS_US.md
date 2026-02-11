# CAMELS-US Dataset Usage Guide

> This document summarizes how to use the CAMELS-US data that fits the NeuralHydrology project layout.

---

## 1. Data Location

The CAMELS-US dataset is **not included** in the Git repository due to its size. You must download it and place it under the data/ directory like this:

`
neuralhydrology/
鈹溾攢鈹€ data/
鈹?  鈹斺攢鈹€ CAMELS_US/            <-- CAMELS-US data root
鈹?      鈹溾攢鈹€ basin_mean_forcing/
鈹?      鈹溾攢鈹€ basin_metadata/
鈹?      鈹溾攢鈹€ camels_attributes_v2.0/
鈹?      鈹溾攢鈹€ discharge/
鈹?      鈹斺攢鈹€ ...
鈹斺攢鈹€ scripts/
`

**Important**: You need to download and unzip CAMELS-US into data/CAMELS_US/.

---

## 2. What is CAMELS-US?

CAMELS-US is a widely used large-sample hydrology dataset for the United States. It provides:
- Daily meteorological forcing data (multiple products)
- Discharge time series (observed streamflow)
- Static basin attributes (topography, soils, land cover, climate indices)

---

## 3. Download and Prepare Data

### 3.1 Manual Download

Use the official CAMELS-US release from NCAR/UCAR or the project documentation.
After download, unzip into:

`
<repo>/data/CAMELS_US
`

Make sure the following subdirectories exist (names may vary slightly by release):

`
CAMELS_US/
鈹溾攢鈹€ basin_mean_forcing/
鈹溾攢鈹€ basin_metadata/
鈹溾攢鈹€ camels_attributes_v2.0/
鈹溾攢鈹€ discharge/
鈹斺攢鈹€ ...
`

---

## 4. Use in Other Projects (Python Examples)

### 4.1 Basic Setup

`python
from pathlib import Path
DATA_DIR = Path('G:/github/pycharm/projects/neuralhydrology/data/CAMELS_US')
# or Linux: Path('/path/to/neuralhydrology/data/CAMELS_US')
`

### 4.2 Read Forcing and Streamflow

The CAMELS-US data format varies by forcing product. For details, refer to the CAMELS-US documentation or use NeuralHydrology鈥檚 dataset loader.

---

## 5. Use in NeuralHydrology Config

Example config snippet:

`yaml
dataset: camels_us
data_dir: data/CAMELS_US

forcings: maurer_extended
dynamic_inputs:
  - prcp(mm/day)
  - srad(W/m2)
  - tmax(C)
  - tmin(C)
  - vp(Pa)

target_variables:
  - QObs(mm/d)
`

---

**Document date**: 2026-01-13
