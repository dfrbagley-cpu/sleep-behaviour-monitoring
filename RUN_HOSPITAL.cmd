@echo off
setlocal
pushd "%~dp0" || exit /b 1
if defined SBM_RSCRIPT (
  "%SBM_RSCRIPT%" --vanilla run_hospital.R
) else (
  Rscript --vanilla run_hospital.R
)
set "SBM_EXIT=%ERRORLEVEL%"
if not "%SBM_EXIT%"=="0" echo Report failed. If Rscript was not found, open run_hospital.R in RStudio and click Source.
popd
pause
exit /b %SBM_EXIT%
