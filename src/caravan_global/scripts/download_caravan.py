#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Caravan Dataset Downloader
==========================

下载 Caravan 全球水文数据集（用于 neuralhydrology 训练）

数据来源：
- NetCDF 版本 (推荐): https://zenodo.org/records/15529786 (Version 1.6)
- CSV 版本: https://zenodo.org/records/15530021

使用方法：
    python download_caravan.py --output_dir /path/to/save/Caravan
    python download_caravan.py --output_dir /path/to/save/Caravan --format csv
    python download_caravan.py --output_dir /path/to/save/Caravan --version 1.4

注意事项：
- NetCDF 版本约 24.8 GB（压缩后），推荐用于 neuralhydrology
- CSV 版本约 15+ GB（压缩后）
- 下载需要稳定的网络连接
- 建议使用 SSD 或高速硬盘存储
"""

import argparse
import hashlib
import os
import sys
import tarfile
import zipfile
from pathlib import Path
from typing import Optional

# 尝试导入可选的下载库
try:
    import requests
    from tqdm import tqdm
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

try:
    import urllib.request
    HAS_URLLIB = True
except ImportError:
    HAS_URLLIB = False


# Zenodo 记录信息
# 版本 1.6 (最新): NetCDF 和 CSV 分开
ZENODO_RECORDS = {
    "1.6": {
        "netcdf": {
            "record_id": "15529786",
            "files": [
                {
                    "name": "Caravan-nc.tar.gz",
                    "url": "https://zenodo.org/records/15529786/files/Caravan-nc.tar.gz",
                    "md5": "ad3a7767db059f218380e9cce5f72452",
                    "size_gb": 24.8
                },
                {
                    "name": "Caravan-code.zip",
                    "url": "https://zenodo.org/records/15529786/files/Caravan-code.zip",
                    "md5": "33df29a80c56d74e94da44f9feeaa357",
                    "size_mb": 4.2
                }
            ]
        },
        "csv": {
            "record_id": "15530021",
            "files": [
                {
                    "name": "Caravan-csv.tar.gz",
                    "url": "https://zenodo.org/records/15530021/files/Caravan-csv.tar.gz",
                    "md5": None,  # 需要从 Zenodo 确认
                    "size_gb": 15.0  # 估计值
                }
            ]
        }
    },
    "1.5": {
        "netcdf": {
            "record_id": "14673536",
            "files": [
                {
                    "name": "Caravan-nc.tar.xz",
                    "url": "https://zenodo.org/records/14673536/files/Caravan-nc.tar.xz",
                    "md5": None,
                    "size_gb": 20.0
                }
            ]
        }
    },
    "1.4": {
        "netcdf": {
            "record_id": "10968468",
            "files": [
                {
                    "name": "Caravan-nc.tar.xz",
                    "url": "https://zenodo.org/records/10968468/files/Caravan-nc.tar.xz",
                    "md5": None,
                    "size_gb": 18.0
                }
            ]
        }
    },
    "1.2": {
        "all": {
            "record_id": "7944025",
            "files": [
                {
                    "name": "Caravan.zip",
                    "url": "https://zenodo.org/records/7944025/files/Caravan.zip",
                    "md5": "bd9d6e9dd1d0da0731b53678f551f8f9",
                    "size_gb": 12.5
                }
            ]
        }
    }
}


def check_dependencies():
    """检查必要的依赖"""
    if not HAS_REQUESTS:
        print("警告: 未安装 requests 和 tqdm，将使用 urllib（无进度条）")
        print("建议安装: pip install requests tqdm")
    return HAS_REQUESTS or HAS_URLLIB


def calculate_md5(filepath: Path, chunk_size: int = 8192) -> str:
    """计算文件的 MD5 哈希值"""
    md5_hash = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(chunk_size), b""):
            md5_hash.update(chunk)
    return md5_hash.hexdigest()


def download_with_requests(url: str, filepath: Path, expected_md5: Optional[str] = None, 
                           max_retries: int = 10, retry_delay: int = 5) -> bool:
    """使用 requests 下载文件（带进度条和断点续传支持）
    
    Parameters
    ----------
    url : str
        下载链接
    filepath : Path
        保存路径
    expected_md5 : str, optional
        期望的 MD5 值用于验证
    max_retries : int
        最大重试次数（默认 10 次）
    retry_delay : int
        重试间隔秒数（默认 5 秒）
    """
    import time
    
    # 检查是否存在部分下载的文件
    temp_filepath = Path(str(filepath) + ".part")
    
    for attempt in range(max_retries):
        try:
            # 获取已下载的字节数（用于断点续传）
            resume_byte = 0
            if temp_filepath.exists():
                resume_byte = temp_filepath.stat().st_size
                print(f"发现已下载 {resume_byte / 1024 / 1024:.1f} MB，尝试断点续传...")
            
            # 设置 Range 头以支持断点续传
            headers = {}
            if resume_byte > 0:
                headers['Range'] = f'bytes={resume_byte}-'
            
            response = requests.get(url, stream=True, headers=headers, timeout=60)
            
            # 检查服务器是否支持断点续传
            if resume_byte > 0 and response.status_code == 206:
                print("服务器支持断点续传，继续下载...")
                mode = 'ab'  # 追加模式
            elif response.status_code == 200:
                if resume_byte > 0:
                    print("服务器不支持断点续传，重新下载...")
                resume_byte = 0
                mode = 'wb'  # 覆盖模式
            else:
                response.raise_for_status()
                mode = 'wb'
            
            # 获取总文件大小
            content_length = int(response.headers.get('content-length', 0))
            total_size = resume_byte + content_length
            
            with open(temp_filepath, mode) as f:
                with tqdm(total=total_size, initial=resume_byte, unit='B', 
                         unit_scale=True, desc=filepath.name) as pbar:
                    for chunk in response.iter_content(chunk_size=32768):  # 增大块大小提高效率
                        if chunk:
                            f.write(chunk)
                            pbar.update(len(chunk))
            
            # 下载完成，重命名文件
            if temp_filepath.exists():
                if filepath.exists():
                    filepath.unlink()
                temp_filepath.rename(filepath)
            
            # 验证 MD5
            if expected_md5:
                print(f"验证 MD5: {filepath.name}...")
                actual_md5 = calculate_md5(filepath)
                if actual_md5 != expected_md5:
                    print(f"警告: MD5 不匹配! 期望: {expected_md5}, 实际: {actual_md5}")
                    print("文件可能损坏，删除后重试...")
                    filepath.unlink()
                    return False
                print(f"MD5 验证通过!")
            
            return True
            
        except (requests.exceptions.RequestException, IOError, OSError) as e:
            print(f"\n下载中断 (尝试 {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                print(f"等待 {retry_delay} 秒后重试...")
                time.sleep(retry_delay)
                # 指数退避：每次失败后等待时间翻倍，最大 60 秒
                retry_delay = min(retry_delay * 2, 60)
            else:
                print(f"达到最大重试次数，下载失败。")
                print(f"部分文件已保存为: {temp_filepath}")
                print(f"重新运行脚本可继续下载。")
                return False
    
    return False


def download_with_urllib(url: str, filepath: Path, expected_md5: Optional[str] = None) -> bool:
    """使用 urllib 下载文件（无进度条）"""
    try:
        print(f"下载中: {url}")
        print(f"保存到: {filepath}")
        print("（这可能需要很长时间，请耐心等待...）")
        
        urllib.request.urlretrieve(url, filepath)
        
        # 验证 MD5
        if expected_md5:
            print(f"验证 MD5: {filepath.name}...")
            actual_md5 = calculate_md5(filepath)
            if actual_md5 != expected_md5:
                print(f"警告: MD5 不匹配! 期望: {expected_md5}, 实际: {actual_md5}")
                return False
            print(f"MD5 验证通过!")
        
        return True
        
    except Exception as e:
        print(f"下载失败: {e}")
        return False


def download_file(url: str, filepath: Path, expected_md5: Optional[str] = None) -> bool:
    """下载文件（自动选择可用的方法，支持断点续传）"""
    # 检查是否有部分下载的文件
    temp_filepath = Path(str(filepath) + ".part")
    
    if filepath.exists():
        print(f"文件已存在: {filepath}")
        if expected_md5:
            print("验证现有文件的 MD5...")
            actual_md5 = calculate_md5(filepath)
            if actual_md5 == expected_md5:
                print("MD5 验证通过，跳过下载")
                return True
            else:
                print("MD5 不匹配，重新下载...")
                filepath.unlink()
        else:
            print("跳过下载（如需重新下载，请删除现有文件）")
            return True
    
    if HAS_REQUESTS:
        return download_with_requests(url, filepath, expected_md5)
    elif HAS_URLLIB:
        print("警告: urllib 不支持断点续传，建议安装 requests: pip install requests tqdm")
        return download_with_urllib(url, filepath, expected_md5)
    else:
        print("错误: 没有可用的下载库！")
        return False


def extract_archive(filepath: Path, output_dir: Path) -> bool:
    """解压归档文件"""
    print(f"解压中: {filepath.name}...")
    
    try:
        if filepath.suffix == '.zip':
            with zipfile.ZipFile(filepath, 'r') as zf:
                zf.extractall(output_dir)
        elif filepath.name.endswith('.tar.gz') or filepath.name.endswith('.tgz'):
            with tarfile.open(filepath, 'r:gz') as tf:
                tf.extractall(output_dir)
        elif filepath.name.endswith('.tar.xz'):
            with tarfile.open(filepath, 'r:xz') as tf:
                tf.extractall(output_dir)
        elif filepath.name.endswith('.tar'):
            with tarfile.open(filepath, 'r') as tf:
                tf.extractall(output_dir)
        else:
            print(f"不支持的归档格式: {filepath.suffix}")
            return False
        
        print(f"解压完成!")
        return True
        
    except Exception as e:
        print(f"解压失败: {e}")
        return False


def get_available_versions() -> list:
    """获取可用的版本列表"""
    return list(ZENODO_RECORDS.keys())


def get_available_formats(version: str) -> list:
    """获取指定版本可用的格式"""
    if version not in ZENODO_RECORDS:
        return []
    return list(ZENODO_RECORDS[version].keys())


def print_download_info(version: str, format_type: str):
    """打印下载信息"""
    print("\n" + "=" * 60)
    print("Caravan 数据集下载器")
    print("=" * 60)
    print(f"版本: {version}")
    print(f"格式: {format_type}")
    
    if version in ZENODO_RECORDS:
        record = ZENODO_RECORDS[version]
        if format_type in record:
            files = record[format_type]["files"]
            total_size = sum(f.get("size_gb", 0) for f in files)
            print(f"预计总大小: ~{total_size:.1f} GB")
            print(f"文件数量: {len(files)}")
    
    print("=" * 60 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Caravan 全球水文数据集下载器",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 下载最新版 NetCDF 格式（推荐）
  python download_caravan.py --output_dir ./data/Caravan

  # 下载 CSV 格式
  python download_caravan.py --output_dir ./data/Caravan --format csv

  # 下载特定版本
  python download_caravan.py --output_dir ./data/Caravan --version 1.4

  # 只下载不解压
  python download_caravan.py --output_dir ./data/Caravan --no-extract

可用版本: """ + ", ".join(get_available_versions())
    )
    
    parser.add_argument(
        "--output_dir", "-o",
        type=str,
        required=True,
        help="数据保存目录"
    )
    
    parser.add_argument(
        "--version", "-v",
        type=str,
        default="1.6",
        choices=get_available_versions(),
        help="Caravan 版本 (默认: 1.6)"
    )
    
    parser.add_argument(
        "--format", "-f",
        type=str,
        default="netcdf",
        choices=["netcdf", "csv", "all"],
        help="数据格式 (默认: netcdf，推荐用于 neuralhydrology)"
    )
    
    parser.add_argument(
        "--no-extract",
        action="store_true",
        help="只下载，不解压"
    )
    
    parser.add_argument(
        "--keep-archive",
        action="store_true",
        help="解压后保留原始压缩包"
    )
    
    parser.add_argument(
        "--download-code",
        action="store_true",
        help="同时下载 Caravan 代码包"
    )
    
    args = parser.parse_args()
    
    # 检查依赖
    if not check_dependencies():
        print("错误: 没有可用的下载库！")
        sys.exit(1)
    
    # 创建输出目录
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # 获取下载信息
    version = args.version
    format_type = args.format
    
    if version not in ZENODO_RECORDS:
        print(f"错误: 版本 {version} 不存在")
        sys.exit(1)
    
    record = ZENODO_RECORDS[version]
    
    # 处理格式选择
    if format_type not in record:
        available_formats = get_available_formats(version)
        if len(available_formats) == 1:
            format_type = available_formats[0]
            print(f"版本 {version} 只有 {format_type} 格式，自动选择")
        else:
            print(f"错误: 版本 {version} 不支持 {format_type} 格式")
            print(f"可用格式: {available_formats}")
            sys.exit(1)
    
    print_download_info(version, format_type)
    
    # 下载文件
    files_to_download = record[format_type]["files"]
    
    # 如果需要下载代码
    if args.download_code and format_type == "netcdf" and version == "1.6":
        code_file = {
            "name": "Caravan-code.zip",
            "url": "https://zenodo.org/records/15529786/files/Caravan-code.zip",
            "md5": "33df29a80c56d74e94da44f9feeaa357",
            "size_mb": 4.2
        }
        if code_file not in files_to_download:
            files_to_download = files_to_download + [code_file]
    
    downloaded_files = []
    
    for file_info in files_to_download:
        filepath = output_dir / file_info["name"]
        print(f"\n正在下载: {file_info['name']}")
        
        if "size_gb" in file_info:
            print(f"文件大小: ~{file_info['size_gb']:.1f} GB")
        elif "size_mb" in file_info:
            print(f"文件大小: ~{file_info['size_mb']:.1f} MB")
        
        success = download_file(
            url=file_info["url"],
            filepath=filepath,
            expected_md5=file_info.get("md5")
        )
        
        if success:
            downloaded_files.append(filepath)
        else:
            print(f"警告: 下载 {file_info['name']} 失败")
    
    # 解压文件
    if not args.no_extract:
        for filepath in downloaded_files:
            if filepath.suffix in ['.zip', '.gz', '.xz'] or '.tar' in filepath.name:
                extract_archive(filepath, output_dir)
                
                # 删除压缩包
                if not args.keep_archive:
                    print(f"删除压缩包: {filepath.name}")
                    filepath.unlink()
    
    # 打印完成信息
    print("\n" + "=" * 60)
    print("下载完成!")
    print("=" * 60)
    print(f"数据保存在: {output_dir.absolute()}")
    print("\n后续步骤:")
    print("1. 确认目录结构包含 attributes/ 和 timeseries/ 文件夹")
    print("2. 在训练配置文件中设置:")
    print(f"   data_dir: {output_dir.absolute()}")
    print("   dataset: caravan")
    print("=" * 60)


if __name__ == "__main__":
    main()
