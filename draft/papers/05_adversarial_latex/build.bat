@echo off
REM Build script for adversarial robustness paper (WRR)
REM Usage: double-click or run from command line

set MIKTEX=C:\Users\yiqun\AppData\Local\Programs\MiKTeX\miktex\bin\x64
cd /d "%~dp0"

echo [1/4] pdflatex (1st pass)...
"%MIKTEX%\pdflatex.exe" -interaction=nonstopmode main.tex >nul 2>&1

echo [2/4] bibtex...
"%MIKTEX%\bibtex.exe" main >nul 2>&1

echo [3/4] pdflatex (2nd pass)...
"%MIKTEX%\pdflatex.exe" -interaction=nonstopmode main.tex >nul 2>&1

echo [4/4] pdflatex (3rd pass)...
"%MIKTEX%\pdflatex.exe" -interaction=nonstopmode main.tex >nul 2>&1

echo [5/7] pdflatex SI (1st pass)...
"%MIKTEX%\pdflatex.exe" -interaction=nonstopmode supporting_information.tex >nul 2>&1

echo [6/7] pdflatex SI (2nd pass)...
"%MIKTEX%\pdflatex.exe" -interaction=nonstopmode supporting_information.tex >nul 2>&1

echo [7/7] Done.
if exist main.pdf (
    echo BUILD OK: main.pdf generated
) else (
    echo BUILD FAILED - check main.log for errors
)
if exist supporting_information.pdf (
    echo BUILD OK: supporting_information.pdf generated
) else (
    echo BUILD FAILED - check supporting_information.log for errors
)
pause
