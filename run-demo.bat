@echo off
cd /d "%~dp0"
where Rscript >nul 2>nul
if errorlevel 1 (
  echo Install R and add its bin folder to PATH, then reopen this launcher.
  pause
  exit /b 1
)
Rscript --vanilla run.R --demo
pause
