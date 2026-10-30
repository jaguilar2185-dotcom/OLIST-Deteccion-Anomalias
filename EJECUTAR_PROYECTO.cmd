@echo off
setlocal
cd /d "%~dp0"
python ejecutar_proyecto.py
if errorlevel 1 (
    echo El proceso fallo. Revisa el mensaje anterior; no presentes resultados como actualizados.
    pause
    exit /b 1
)
pause
