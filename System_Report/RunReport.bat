@echo off
title System Report Generator
color 0A
echo.
echo  Starting System Report Generator...
echo  (If prompted about execution policy, type Y and press Enter)
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0SystemReport.ps1"
echo.
pause
