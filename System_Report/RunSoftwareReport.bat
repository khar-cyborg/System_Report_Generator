@echo off
title Software Report Generator
color 0A
echo.
echo  Starting Software Report Generator...
echo  (Run as Administrator for best results)
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0SoftwareReport.ps1"
echo.
pause
