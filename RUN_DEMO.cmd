@echo off
setlocal
pushd "%~dp0" || exit /b 1
if defined SBM_RSCRIPT (
  "%SBM_RSCRIPT%" --vanilla run.R --demo
) else (
  Rscript --vanilla run.R --demo
)
set "SBM_EXIT=%ERRORLEVEL%"
if not "%SBM_EXIT%"=="0" echo Demo failed. Check that R and required packages are available.
popd
pause
exit /b %SBM_EXIT%
