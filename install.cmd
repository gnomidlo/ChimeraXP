@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\ChimeraXP.ps1" -Source Local %*
set "CXP_RESULT=%ERRORLEVEL%"
echo.
if not "%CXP_RESULT%"=="0" echo Wystapil blad instalacji.
pause
exit /b %CXP_RESULT%