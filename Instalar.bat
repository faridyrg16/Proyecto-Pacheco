@echo off
title Instalador - Auditoria de Windows
:: Verificar si se está ejecutando como Administrador
openfiles >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando privilegios de Administrador...
    powershell -Command "Start-Process '%~dp0Instalar.bat' -Verb RunAs"
    exit /b
)

:: Si ya está elevado, ejecutar el script setup.ps1
cd /d "%~dp0"
echo =========================================================
echo  Iniciando Instalador del Sistema de Auditoria...
echo =========================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
echo.
echo Presione cualquier tecla para salir...
pause >nul
