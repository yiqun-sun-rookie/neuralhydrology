<#
.SYNOPSIS
    NeuralHydrology HPC 迁移打包工具
.DESCRIPTION
    此脚本用于将项目代码和数据打包成适合上传 HPC 的压缩包。
    它会自动排除不必要的大文件（如 runs, output 等）。
    使用 tar 命令进行压缩（Windows 10/11 自带）。
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = "G:\github\pycharm\projects\neuralhydrology"
$DistDir = "$ProjectRoot\dist_hpc"

# 确保输出目录存在
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

function Pack-Code {
    Write-Host "[1/3] 正在打包核心代码 (nh_code.tar.gz)..." -ForegroundColor Cyan
    $excludes = @(
        "--exclude=data",
        "--exclude=runs", 
        "--exclude=outputs",
        "--exclude=results",
        "--exclude=logs",
        "--exclude=external",
        "--exclude=.git",
        "--exclude=__pycache__",
        "--exclude=*.egg-info",
        "--exclude=.idea",
        "--exclude=.vscode",
        "--exclude=dist_hpc"
    )
    
    # 切换到上级目录以打包整个 neuralhydrology 文件夹
    Push-Location "$ProjectRoot\.."
    $cmd = "tar -czvf ""$DistDir\nh_code.tar.gz"" $excludes neuralhydrology"
    Invoke-Expression $cmd
    Pop-Location
    
    Write-Host "✅ 代码打包完成: $DistDir\nh_code.tar.gz" -ForegroundColor Green
    Write-Host ""
}

function Pack-Namou {
    Write-Host "[2/3] 正在打包 Namou Kuwei 数据 (data_namou.tar.gz)..." -ForegroundColor Cyan
    if (Test-Path "$ProjectRoot\data\namou_kuwei_hourly") {
        Push-Location "$ProjectRoot"
        # 只打包 namou_kuwei_hourly 目录
        tar -czvf "$DistDir\data_namou.tar.gz" data/namou_kuwei_hourly
        Pop-Location
        Write-Host "✅ Namou 数据打包完成: $DistDir\data_namou.tar.gz" -ForegroundColor Green
    } else {
        Write-Host "⚠️ 未找到 Namou Kuwei 数据目录，跳过。" -ForegroundColor Yellow
    }
    Write-Host ""
}

function Pack-Caravan-Split {
    Write-Host "[3/3] 正在打包 Caravan 数据 (分卷模式)..." -ForegroundColor Cyan
    $CaravanPath = "$ProjectRoot\data\Caravan"
    
    if (-not (Test-Path $CaravanPath)) {
        Write-Host "⚠️ 未找到 Caravan 数据目录，跳过。" -ForegroundColor Yellow
        return
    }

    Push-Location "$ProjectRoot"

    # 1. 打包除了 timeseries 的所有内容 (Meta info)
    Write-Host "  -> 正在打包元数据 (caravan_meta.tar.gz)..." -ForegroundColor Yellow
    tar -czvf "$DistDir\caravan_meta.tar.gz" --exclude="data/Caravan/timeseries" data/Caravan
    
    # 2. 单独打包 timeseries (这部分最大)
    if (Test-Path "$CaravanPath\timeseries") {
        Write-Host "  -> 正在打包时间序列数据 (caravan_ts.tar.gz)... 这可能需要很长时间!" -ForegroundColor Yellow
        # 这里为了简化，先打包成一个大文件。对于 WinSCP 断点续传，一个大文件通常是可以接受的。
        # 如果需要拆分，建议手动使用 7-zip 的分卷功能。
        tar -czvf "$DistDir\caravan_ts.tar.gz" data/Caravan/timeseries
    }
    
    Pop-Location
    Write-Host "✅ Caravan 数据打包完成" -ForegroundColor Green
}

# --- 主程序 ---
Write-Host "=== NeuralHydrology HPC 打包工具 ===" -ForegroundColor Magenta
Write-Host "打包文件将保存在: $DistDir"
Write-Host ""

Pack-Code
Pack-Namou
Pack-Caravan-Split

Write-Host ""
Write-Host "=== 所有任务完成 ===" -ForegroundColor Magenta
Write-Host "请使用 WinSCP 将 $DistDir 目录下的所有文件上传到 HPC 的 ~/neuralhydrology 目录同级 (或者在上面解压)。"
Write-Host "上传顺序建议: nh_code -> data_namou -> caravan_meta -> caravan_ts"
