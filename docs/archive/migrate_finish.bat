@echo off
echo ============================================
echo  NeuralHydrology Migration Script
echo ============================================
echo.
echo This script will:
echo   1. Rename F:\...\neuralhydrology to neuralhydrology_backup
echo   2. Create symbolic link from F: to G:
echo.
echo IMPORTANT: Close Cursor IDE before running!
echo.
pause

echo.
echo Step 1: Renaming original folder to backup...
ren "F:\github\pycharm\projects\neuralhydrology" "neuralhydrology_backup"
if %errorlevel% neq 0 (
    echo ERROR: Failed to rename. Make sure Cursor is closed!
    pause
    exit /b 1
)
echo OK: Renamed to neuralhydrology_backup

echo.
echo Step 2: Creating symbolic link...
mklink /D "F:\github\pycharm\projects\neuralhydrology" "G:\github\pycharm\projects\neuralhydrology"
if %errorlevel% neq 0 (
    echo ERROR: Failed to create link. Try running as Administrator!
    pause
    exit /b 1
)
echo OK: Symbolic link created

echo.
echo ============================================
echo  Migration Complete!
echo ============================================
echo.
echo You can now reopen Cursor at:
echo   F:\github\pycharm\projects\neuralhydrology
echo.
echo (It will actually use G: drive now)
echo.
pause

