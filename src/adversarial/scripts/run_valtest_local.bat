@echo off
REM Run adversarial evaluation on val+test basins (135 basins) locally with GPU
REM Expected runtime: ~3-4 hours total on RTX 4070 Ti
REM Output: results/adversarial_eval/full/results_valtest_apgd.json
REM         results/adversarial_eval/full/results_valtest_fgsm.json

cd /d "%~dp0\..\..\..\"

echo ============================================================
echo Adversarial eval on 135 val+test basins (RTX 4070 Ti)
echo ============================================================

echo.
echo [1/2] Auto-PGD (eps=0.1, Lp, untargeted) — ~2-3 hours
echo Start: %date% %time%
python src/adversarial/scripts/run_adversarial_eval.py ^
    --config src/adversarial/configs/full_eval.yaml ^
    --basin-file src/adversarial/data/valtest_135_basins.txt ^
    --attack auto_pgd ^
    --epsilon 0.1 ^
    --constraint lp ^
    --target untargeted ^
    --n-samples 1 ^
    --output-suffix valtest_apgd
echo End:   %date% %time%

echo.
echo [2/2] FGSM (eps=0.1, Lp, untargeted) — ~10-15 minutes
echo Start: %date% %time%
python src/adversarial/scripts/run_adversarial_eval.py ^
    --config src/adversarial/configs/full_eval.yaml ^
    --basin-file src/adversarial/data/valtest_135_basins.txt ^
    --attack fgsm ^
    --epsilon 0.1 ^
    --constraint lp ^
    --target untargeted ^
    --n-samples 1 ^
    --output-suffix valtest_fgsm
echo End:   %date% %time%

echo.
echo ============================================================
echo Done! Results saved to results/adversarial_eval/full/
echo   - results_valtest_apgd.json
echo   - results_valtest_fgsm.json
echo ============================================================
pause
