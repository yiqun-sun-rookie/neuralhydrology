@echo off
chcp 65001 >nul
echo ============================================
echo  MTSMamba Phase 2v2 — Sync to HPC
echo ============================================
echo.
echo 输入密码+OTP后全自动同步
echo.

"F:\Program Files (x86)\WinSCP\WinSCP.com" ^
  /ini=nul ^
  /script="%~dp0winscp_sync.txt"

echo.
if %ERRORLEVEL% EQU 0 (
    echo [OK] 同步完成！
    echo.
    echo 下一步：在 HPC 终端运行:
    echo   cd ~/neuralhydrology
    echo   find neuralhydrology -type d -name __pycache__ -exec rm -rf {} + 2^>/dev/null
    echo   bash src/mts_mamba_global_transfer/hpc/check_mamba_deps.sh
    echo   sbatch src/mts_mamba_global_transfer/hpc/submit_phase2v2_mtsmamba.slurm
) else (
    echo [FAIL] 同步失败，错误码: %ERRORLEVEL%
    echo 请检查上方日志
)
echo.
pause
