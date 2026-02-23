$User = "sunyiq"
$HostName = "hpcbh.hhu.edu.cn"
$RemoteProjectPath = "~/neuralhydrology/"

Write-Host "Task 41 upload helper" -ForegroundColor Cyan
Write-Host "You will be prompted for Password + OTP each step." -ForegroundColor Yellow

ssh ${User}@${HostName} "mkdir -p ~/neuralhydrology/src/mts_mamba_global_transfer ~/neuralhydrology/logs/41_mts_mamba_global_transfer ~/neuralhydrology/results/41_mts_mamba_global_transfer"
if ($LASTEXITCODE -ne 0) {
  Write-Host "Failed to create remote directories." -ForegroundColor Red
  exit 1
}

scp -r src/mts_mamba_global_transfer ${User}@${HostName}:${RemoteProjectPath}src/
Write-Host "Task 41 files uploaded." -ForegroundColor Green
