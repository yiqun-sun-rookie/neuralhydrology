#!/usr/bin/env python
"""
快速创建新站点目录结构和配置模板

用法：
    python scripts/new_site.py <站点名> <数据目录>
    
示例：
    python scripts/new_site.py mekong_vientiane F:/data/mekong_hourly
    
会创建：
    src/<站点名>/configs/
    并复制已验证的配置模板，只需修改雨量站列表即可训练
"""
import sys
import shutil
from pathlib import Path

# 已验证的配置模板（从 namou_kuwei 复制）
TEMPLATE_DIR = Path(__file__).parent.parent / "src/namou_kuwei/configs/no_leak"

def create_site(site_name: str, data_dir: str):
    """创建新站点目录结构"""
    
    base = Path(__file__).parent.parent
    site_dir = base / "experiments" / site_name / "configs"
    
    if site_dir.exists():
        print(f"站点已存在: {site_dir}")
        return
    
    # 创建目录
    site_dir.mkdir(parents=True)
    print(f"创建目录: {site_dir}")
    
    # 复制核心配置模板（只复制最有价值的几个）
    templates = [
        "03_with_ar/rain_ar_LT1h.yml",      # 1h 预报基准
        "05_leadtime/rain_ar_LT24h.yml",    # 24h Seq-to-One
        "06_seq2seq/seq2seq_ar24lag_24h.yml", # 24h Seq-to-Seq
    ]
    
    for tpl in templates:
        src = TEMPLATE_DIR / tpl
        if not src.exists():
            print(f"模板不存在，跳过: {src}")
            continue
        
        # 读取并替换
        content = src.read_text(encoding="utf-8")
        content = content.replace("namou_kuwei", site_name)
        content = content.replace(
            "F:/github/pycharm/projects/neuralhydrology/data/namou_kuwei_hourly",
            data_dir.replace("\\", "/")
        )
        
        # 写入新位置
        dst = site_dir / src.name
        dst.write_text(content, encoding="utf-8")
        print(f"  生成配置: {dst.name}")
    
    print(f"""
完成！下一步：
1. 编辑 {site_dir}/*.yml，修改 dynamic_inputs 为你的雨量站列表
2. 检查数据: python scripts/check_site.py {site_name}
3. 训练: python -m neuralhydrology.nh_run train --config-file {site_dir}/rain_ar_LT1h.yml
""")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    
    create_site(sys.argv[1], sys.argv[2])

