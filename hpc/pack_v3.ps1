<#
.SYNOPSIS
    NeuralHydrology HPC 迁移打包工具 v3
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = "G:\github\pycharm\projects\neuralhydrology"
$DistDir = "$ProjectRoot\dist_hpc"

if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

function Run-Tar {
    param([string[]]$ArgsList)
    Write-Host "Executing: tar $ArgsList" -ForegroundColor DarkGray
    & tar $ArgsList
    if ($LASTEXITCODE -ne 0) {
        Write-Error "tar command failed with exit code $LASTEXITCODE"
    }
}

function Pack-Code {
    Write-Host "[1/3] Packing Code (nh_code.tar.gz)..." -ForegroundColor Cyan
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
    $tarArgs = @("czvf", "$DistDir\nh_code.tar.gz") + $excludes + @("neuralhydrology")
    Run-Tar $tarArgs
    Pop-Location
    
    Write-Host "Done: $DistDir\nh_code.tar.gz" -ForegroundColor Green
    Write-Host ""
}

function Pack-Namou {
    Write-Host "[2/3] Packing Namou Data (data_namou.tar.gz)..." -ForegroundColor Cyan
    if (Test-Path "$ProjectRoot\data\namou_kuwei_hourly") {
        Push-Location "$ProjectRoot"
        $tarArgs = @("czvf", "$DistDir\data_namou.tar.gz", "data/namou_kuwei_hourly")
        Run-Tar $tarArgs
        Pop-Location
        Write-Host "Done: $DistDir\data_namou.tar.gz" -ForegroundColor Green
    } else {
        Write-Host "Skipping Namou (Not found)" -ForegroundColor Yellow
    }
    Write-Host ""
}

function Pack-Caravan-Split {
    Write-Host "[3/3] Packing Caravan Data..." -ForegroundColor Cyan
    $CaravanPath = "$ProjectRoot\data\Caravan"
    
    if (-not (Test-Path $CaravanPath)) {
        Write-Host "Skipping Caravan (Not found)" -ForegroundColor Yellow
        return
    }

    Push-Location "$ProjectRoot"

    # 1. Meta info
    Write-Host "  -> Packing Meta (caravan_meta.tar.gz)..." -ForegroundColor Yellow
    $tarArgs = @(
        "czvf", 
        "$DistDir\caravan_meta.tar.gz", 
        "--exclude=data/Caravan/timeseries", 
        "--exclude=data/Caravan/*.tar.gz",
        "data/Caravan"
    )
    Run-Tar $tarArgs
    
    # 2. Timeseries
    if (Test-Path "$CaravanPath\timeseries") {
        Write-Host "  -> Packing Series (caravan_ts.tar.gz)..." -ForegroundColor Yellow
        $tarArgs = @("czvf", "$DistDir\caravan_ts.tar.gz", "data/Caravan/timeseries")
        Run-Tar $tarArgs
    }
    
    Pop-Location
    Write-Host "Done Caravan" -ForegroundColor Green
}

# --- Main ---
Write-Host "=== NeuralHydrology HPC Packing Tool v3 ===" -ForegroundColor Magenta
Write-Host "Output: $DistDir"
Write-Host ""

Pack-Code
Pack-Namou
Pack-Caravan-Split

Write-Host ""
Write-Host "=== All Done ===" -ForegroundColor Magenta
