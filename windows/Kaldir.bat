@echo off
rem Odak Kilidi kaldirma - sadece "kaldirma izni" gununde calisir
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ProgramData%\OdakKilidi\app\uninstall.ps1"
