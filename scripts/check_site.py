#!/usr/bin/env python
"""
检查站点数据和配置

用法：
    python scripts/check_site.py <站点名>
    python scripts/check_site.py <配置文件路径>
    
检查项：
    1. 数据文件是否存在
    2. 时间拆分是否重叠（泄露检查）
    3. AR 配置是否正确
"""
import sys
import yaml
from pathlib import Path
from datetime import datetime


def parse_date(s):
    """解析日期"""
    for fmt in ["%d/%m/%Y", "%Y-%m-%d"]:
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    raise ValueError(f"无法解析日期: {s}")


def check_config(cfg_path: Path):
    """检查单个配置文件"""
    print(f"\n{'='*50}")
    print(f"检查: {cfg_path.name}")
    print(f"{'='*50}")
    
    with open(cfg_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    
    errors = []
    warnings = []
    
    # 1. 数据路径检查
    data_dir = Path(cfg.get("data_dir", ""))
    if not data_dir.exists():
        errors.append(f"数据目录不存在: {data_dir}")
    else:
        ts_dir = data_dir / "time_series"
        if not ts_dir.exists() or not list(ts_dir.glob("*.csv")):
            errors.append(f"时序数据不存在: {ts_dir}")
    
    # 2. 时间拆分检查
    try:
        train_end = parse_date(cfg["train_end_date"])
        val_start = parse_date(cfg["validation_start_date"])
        val_end = parse_date(cfg["validation_end_date"])
        test_start = parse_date(cfg["test_start_date"])
        
        print(f"  Train: {cfg['train_start_date']} ~ {cfg['train_end_date']}")
        print(f"  Val:   {cfg['validation_start_date']} ~ {cfg['validation_end_date']}")
        print(f"  Test:  {cfg['test_start_date']} ~ {cfg['test_end_date']}")
        
        if train_end >= val_start:
            errors.append(f"Train/Val 重叠: {cfg['train_end_date']} >= {cfg['validation_start_date']}")
        if val_end >= test_start:
            errors.append(f"Val/Test 重叠: {cfg['validation_end_date']} >= {cfg['test_start_date']}")
    except KeyError as e:
        errors.append(f"缺少日期字段: {e}")
    
    # 3. AR 配置检查
    ar_inputs = cfg.get("autoregressive_inputs", [])
    lagged = cfg.get("lagged_features", {})
    model = cfg.get("model", "")
    predict_n = cfg.get("predict_last_n", 1)
    
    if ar_inputs:
        print(f"  AR输入: {ar_inputs}")
        print(f"  滞后配置: {lagged}")
        print(f"  预测步数: {predict_n}")
        
        if model.lower() not in ("arlstm", "earlstm"):
            errors.append(f"使用AR但模型不是arlstm: {model}")
        
        # 检查滞后是否足够
        for ar in ar_inputs:
            if "_shift" in ar:
                shift = int(ar.split("_shift")[1])
                if predict_n > 1 and shift < predict_n:
                    warnings.append(f"Seq2Seq: AR滞后({shift}) < 预测步数({predict_n})，可能泄露")
    
    # 4. qobs 不能在 dynamic_inputs
    if "qobs" in cfg.get("dynamic_inputs", []):
        errors.append("qobs 在 dynamic_inputs 中会导致泄露！应使用 lagged_features")
    
    # 输出结果
    if errors:
        print("\n[错误]")
        for e in errors:
            print(f"  ❌ {e}")
    
    if warnings:
        print("\n[警告]")
        for w in warnings:
            print(f"  ⚠️ {w}")
    
    if not errors and not warnings:
        print("\n✅ 配置正确，无泄露风险")
    
    return len(errors) == 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    arg = sys.argv[1]
    
    # 判断是站点名还是配置文件
    if arg.endswith(".yml") or arg.endswith(".yaml"):
        configs = [Path(arg)]
    else:
        # 站点名，查找所有配置
        site_dir = Path(__file__).parent.parent / "experiments" / arg / "configs"
        if not site_dir.exists():
            print(f"站点目录不存在: {site_dir}")
            sys.exit(1)
        configs = list(site_dir.rglob("*.yml"))
    
    all_ok = True
    for cfg in configs:
        if not check_config(cfg):
            all_ok = False
    
    print(f"\n{'='*50}")
    print(f"共检查 {len(configs)} 个配置，{'全部通过' if all_ok else '存在问题'}")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()

