#!/usr/bin/env python3
"""
备份管理脚本
"""

import os
import shutil
import sys
from pathlib import Path
from datetime import datetime, timedelta

# 设置控制台编码解决中文乱码问题
if sys.platform.startswith('win'):
    try:
        import codecs
        sys.stdout = codecs.getwriter('utf-8')(sys.stdout.detach())
        sys.stderr = codecs.getwriter('utf-8')(sys.stderr.detach())
    except:
        pass

def list_backups():
    """列出所有备份"""
    backup_dir = Path("backups")
    if not backup_dir.exists():
        print("没有找到backups目录")
        return []
    
    backups = []
    for item in backup_dir.iterdir():
        if item.is_dir() and item.name.startswith("backup_"):
            backups.append(item)
    
    return sorted(backups, key=lambda x: x.name, reverse=True)

def show_backup_info(backup_path):
    """显示备份信息"""
    print(f"备份目录: {backup_path.name}")
    
    # 解析时间戳
    try:
        timestamp_str = backup_path.name.replace("backup_", "")
        timestamp = datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")
        print(f"创建时间: {timestamp.strftime('%Y-%m-%d %H:%M:%S')}")
        
        # 计算年龄
        age = datetime.now() - timestamp
        print(f"备份年龄: {age.days} 天")
    except:
        print("创建时间: 无法解析")
    
    # 显示文件列表
    print("包含文件:")
    for file in backup_path.iterdir():
        if file.is_file():
            size_kb = file.stat().st_size / 1024
            print(f"  - {file.name} ({size_kb:.1f} KB)")
    
    print()

def cleanup_old_backups(days=30):
    """清理旧备份"""
    backup_dir = Path("backups")
    if not backup_dir.exists():
        print("没有找到backups目录")
        return
    
    backups = list_backups()
    if not backups:
        print("没有找到备份文件")
        return
    
    cutoff_date = datetime.now() - timedelta(days=days)
    old_backups = []
    
    for backup in backups:
        try:
            timestamp_str = backup.name.replace("backup_", "")
            timestamp = datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")
            if timestamp < cutoff_date:
                old_backups.append(backup)
        except:
            # 如果无法解析时间戳，也认为是旧备份
            old_backups.append(backup)
    
    if not old_backups:
        print(f"没有找到超过 {days} 天的旧备份")
        return
    
    print(f"找到 {len(old_backups)} 个超过 {days} 天的旧备份:")
    for backup in old_backups:
        print(f"  - {backup.name}")
    
    confirm = input(f"\n确认删除这些旧备份? (y/N): ").strip().lower()
    if confirm in ['y', 'yes']:
        for backup in old_backups:
            try:
                shutil.rmtree(backup)
                print(f"已删除: {backup.name}")
            except Exception as e:
                print(f"删除失败 {backup.name}: {e}")
    else:
        print("操作已取消")

def main():
    """主函数"""
    print("=" * 60)
    print("NeuralHydrology 备份管理工具")
    print("=" * 60)
    
    backups = list_backups()
    
    if not backups:
        print("没有找到任何备份")
        return
    
    print(f"找到 {len(backups)} 个备份:")
    print()
    
    for backup in backups:
        show_backup_info(backup)
    
    print("管理选项:")
    print("1. 清理旧备份 (超过30天)")
    print("2. 清理所有备份")
    print("3. 退出")
    
    choice = input("\n请选择 (1-3): ").strip()
    
    if choice == "1":
        cleanup_old_backups(30)
    elif choice == "2":
        confirm = input("确认删除所有备份? (y/N): ").strip().lower()
        if confirm in ['y', 'yes']:
            for backup in backups:
                try:
                    shutil.rmtree(backup)
                    print(f"已删除: {backup.name}")
                except Exception as e:
                    print(f"删除失败 {backup.name}: {e}")
        else:
            print("操作已取消")
    elif choice == "3":
        print("退出")
    else:
        print("无效选择")

if __name__ == "__main__":
    main()
