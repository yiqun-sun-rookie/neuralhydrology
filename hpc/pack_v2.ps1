<#
.SYNOPSIS
    NeuralHydrology HPC 迁移打包工具 (Fixed)
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = "G:\github\pycharm\projects\neuralhydrology"
$DistDir = "$ProjectRoot\dist_hpc"

if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

function Run-Tar {
    param([string[]]$ArgsList)
    Write-Host "Executing download/pack: tar $ArgsList" -ForegroundColor DarkGray
    & tar $ArgsList
    if ($LASTEXITCODE -ne 0) {
        Write-Error "tar command failed with exit code $LASTEXITCODE"
    }
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
    
    Push-Location "$ProjectRoot\.."
    # 打包 neuralhydrology 文件夹
    $tarArgs = @("czvf", "$DistDir\nh_code.tar.gz") + $excludes + @("neuralhydrology")
    Run-Tar $tarArgs
    Pop-Location
    
    Write-Host "✅ 代码打包完成: $DistDir\nh_code.tar.gz" -ForegroundColor Green
    Write-Host ""
}

function Pack-Namou {
    Write-Host "[2/3] 正在打包 Namou Kuwei 数据 (data_namou.tar.gz)..." -ForegroundColor Cyan
    if (Test-Path "$ProjectRoot\data\namou_kuwei_hourly") {
        Push-Location "$ProjectRoot"
        $tarArgs = @("czvf", "$DistDir\data_namou.tar.gz", "data/namou_kuwei_hourly")
        Run-Tar $tarArgs
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

    # 1. Meta info
    Write-Host "  -> 正在打包元数据 (caravan_meta.tar.gz)..." -ForegroundColor Yellow
    # Explicitly use forward slashes for tar compatibility just in case
    # Also exclude nested tar.gz files (like the source archive) to save space/time
    $tarArgs = @("czvf", "$DistDir\caravan_meta.tar.gz", "--exclude=data/Caravan/timeseries", "--exclude=data/Caravan/*.tar.gz", "data/Caravan")
    Run-Tar $tarArgs
    
    # 2. Timeseries
    if (Test-Path "$CaravanPath\timeseries") {
        Write-Host "  -> 正在打包时间序列数据 (caravan_ts.tar.gz)..." -ForegroundColor Yellow
        $tarArgs = @("czvf", "$DistDir\caravan_ts.tar.gz", "data/Caravan/timeseries")
        Run-Tar $tarArgs
    }
    
    Pop-Location
    Write-Host "✅ Caravan 数据打包完成" -ForegroundColor Green
}

# --- Main ---
Write-Host "=== NeuralHydrology HPC Packing Tool v2 ===" -ForegroundColor Magenta
Write-Host "Output: $DistDir"
Write-Host ""

Pack-Code
Pack-Namou
Pack-Caravan-Split

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Magenta
Write-Host "Please upload files in $DistDir to HPC."
