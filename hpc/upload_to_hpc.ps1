$User = "sunyiq"
$HostName = "hpcbh.hhu.edu.cn"
$RemoteDataPath = "~/data/"
$RemoteProjectPath = "~/neuralhydrology/"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   XHPC Upload Helper (Caravan Task)      " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: You will be asked for your Password + OTP for EACH step." -ForegroundColor Yellow
Write-Host "      (Password + Phone Code)" -ForegroundColor Yellow
Write-Host ""

# 1. Create Directories
Write-Host "[Step 1/3] Creating remote directories..." -ForegroundColor Green
ssh ${User}@${HostName} "mkdir -p ~/data/Caravan ~/neuralhydrology/logs ~/neuralhydrology/runs"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error creating directories. Please check your connection/password." -ForegroundColor Red
    exit
}

# 2. Upload Code
Write-Host ""
Write-Host "[Step 2/3] Uploading Code (neuralhydrology, configs, hpc, setup.py)..." -ForegroundColor Green
scp -r neuralhydrology configs hpc setup.py ${User}@${HostName}:${RemoteProjectPath}

# 3. Upload Data
Write-Host ""
Write-Host "[Step 3/3] Uploading Data (Caravan.tar.gz)..." -ForegroundColor Green
if (Test-Path "data\Caravan.tar.gz") {
    scp data\Caravan.tar.gz ${User}@${HostName}:${RemoteDataPath}
} else {
    Write-Host "Error: data\Caravan.tar.gz not found! Did compression finish?" -ForegroundColor Red
}

Write-Host ""
Write-Host "✅ All operations completed." -ForegroundColor Cyan
Write-Host "Next steps on HPC:"
Write-Host "  1. ssh ${User}@${HostName}"
Write-Host "  2. cd ~/data"
Write-Host "  3. tar -xzvf Caravan.tar.gz"
Write-Host "  4. cd ~/neuralhydrology"
Write-Host "  5. sbatch hpc/slurm_caravan_global.sh"
Read-Host "Press Enter to exit"
