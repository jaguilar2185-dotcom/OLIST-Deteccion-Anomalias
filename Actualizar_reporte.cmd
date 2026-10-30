@echo off
setlocal
cd /d "%~dp0"
set "OLIST_RUNTIME=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies"
set "OLIST_INPUT=%~1"
if not defined OLIST_INPUT set "OLIST_INPUT=resultados"
"%OLIST_RUNTIME%\python\python.exe" preparar_reporte.py "%OLIST_INPUT%"
if errorlevel 1 exit /b 1
"%OLIST_RUNTIME%\node\bin\node.exe" --max-old-space-size=12000 generar_reporte.mjs "%OLIST_INPUT%" outputs/olist
if errorlevel 1 exit /b 1
echo Reporte actualizado en outputs\olist\Reporte_OLIST.xlsx
