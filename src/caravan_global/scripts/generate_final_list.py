#!/usr/bin/env python3
"""Generate final valid basins list with correct basin ID format."""

import pandas as pd
from datetime import datetime
from pathlib import Path

DATA_DIR = Path(r"G:\github\pycharm\projects\neuralhydrology\data\Caravan")
df = pd.read_csv(DATA_DIR / "data_alignment_report.csv")
valid = df[df["suitable"]].copy()

# 修正 basin_id 格式: "camels_camels_01013500" -> "camels_01013500"
def fix_basin_id(row):
    basin_id = row["basin_id"]
    subdataset = row["subdataset"]
    # 如果 basin_id 以 subdataset_ 开头两次，去掉第一个
    prefix = f"{subdataset}_"
    if basin_id.startswith(prefix + subdataset):
        # e.g., "camels_camels_01013500" -> "camels_01013500"
        return basin_id[len(prefix):]
    return basin_id

valid["basin_id_fixed"] = valid.apply(fix_basin_id, axis=1)
valid = valid.sort_values("basin_id_fixed")

# 保存最终有效流域列表
output_file = DATA_DIR / "valid_basins.txt"
with open(output_file, "w", encoding="utf-8") as f:
    f.write("# Caravan Valid Basins for Deep Learning Training\n")
    f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    f.write("#\n")
    f.write("# Time periods:\n")
    f.write("#   Training:   1981-01-01 to 2005-12-31 (25 years)\n")
    f.write("#   Validation: 2006-01-01 to 2010-12-31 (5 years)\n")
    f.write("#   Testing:    2011-01-01 to 2020-12-31 (10 years)\n")
    f.write("#\n")
    f.write("# Selection criteria:\n")
    f.write("#   - Min training samples: 1000\n")
    f.write("#   - Min validation samples: 100\n")
    f.write("#   - Min test samples: 100\n")
    f.write("#   - All input features available\n")
    f.write("#\n")
    f.write(f"# Total: {len(valid)} basins\n")
    f.write("#\n")
    f.write("# By dataset:\n")
    for sub in ["camels", "camelsaus", "camelsbr", "camelscl", "camelsgb", "hysets", "lamah"]:
        count = len(valid[valid["subdataset"] == sub])
        f.write(f"#   {sub}: {count}\n")
    f.write("#\n")
    for basin in valid["basin_id_fixed"]:
        f.write(f"{basin}\n")

print(f"已保存: {output_file}")
print(f"有效流域数: {len(valid)}")

# 验证格式
print("\n前5个流域ID:")
for b in valid["basin_id_fixed"].head(5):
    print(f"  {b}")

# 同时更新 src 目录下的副本
src_file = Path(r"G:\github\pycharm\projects\neuralhydrology\src\caravan_global\data\valid_basins.txt")
src_file.parent.mkdir(parents=True, exist_ok=True)
import shutil
shutil.copy(output_file, src_file)
print(f"\n已复制到: {src_file}")
