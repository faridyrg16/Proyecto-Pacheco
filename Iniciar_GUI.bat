@echo off
title Servidor GUI - Auditoria de Windows
cd /d "%~dp0"
echo Iniciando Servidor Web de la GUI...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_gui.ps1"
echo.
echo Servidor HTTP finalizado. Presione cualquier tecla para salir...
pause >nul
