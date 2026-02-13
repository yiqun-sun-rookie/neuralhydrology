@echo off
REM NeuralHydrology HPC 权限设置脚本 (Windows)
REM 注意：此脚本在Windows环境下运行，用于准备HPC部署文件

echo ==========================================
echo NeuralHydrology HPC 权限设置
echo ==========================================

echo 设置脚本执行权限...
echo 注意：在HPC Linux环境中，需要运行以下命令：
echo chmod +x scripts/setup_hpc_environment.sh
echo chmod +x scripts/hpc_deploy.sh
echo chmod +x slurm_jobs/*.slurm

echo.
echo 文件准备完成！
echo 请将以下文件上传到HPC系统：
echo - configs/hpc/
echo - slurm_jobs/
echo - scripts/
echo - HPC_DEPLOYMENT_PLAN.md
echo - HPC_DEPLOYMENT_GUIDE.md

echo.
echo 在HPC系统上运行：
echo bash scripts/hpc_deploy.sh setup

pause


