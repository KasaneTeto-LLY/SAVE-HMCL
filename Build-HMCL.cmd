@echo off
setlocal
cd /d "%~dp0"

rem One-click wrapper: builds HMCL from source with the local patch applied.
rem For study/research only. See README.md for details.
rem Usage: double-click, or run  Build-HMCL.cmd -Clean -GhProxy https://v4.gh-proxy.org

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-HMCL.ps1" -SkipTests %*
set RC=%ERRORLEVEL%

echo.
if "%RC%"=="0" (
  echo Done. Artifacts are in the "out" folder.
) else (
  echo Failed. Exit code %RC%. See the messages above.
)
pause
exit /b %RC%
