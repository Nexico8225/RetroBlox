@echo off
setlocal
cd /d "%~dp0"

set "EXE_PATH=%~dp0RetroBloxPlayer.exe"
if not exist "%EXE_PATH%" (
    if exist "%~dp0RetroBloxLauncher.exe" (
        set "EXE_PATH=%~dp0RetroBloxLauncher.exe"
    ) else if exist "%~dp0Godot_v4.7.2-stable_win64.exe" (
        set "EXE_PATH=%~dp0Godot_v4.7.2-stable_win64.exe"
    )
)

echo ========================================================
echo   RetroBlox 1-Click Web Launcher Setup
echo ========================================================
echo.
echo Target executable: "%EXE_PATH%"
echo.

reg add "HKCU\Software\Classes\retroblox" /ve /d "URL:RetroBlox Protocol" /f >nul
reg add "HKCU\Software\Classes\retroblox" /v "URL Protocol" /d "" /f >nul
reg add "HKCU\Software\Classes\retroblox\shell\open\command" /ve /d "\"%EXE_PATH%\" \"%%1\"" /f >nul

echo [SUCCESS] retroblox:// protocol successfully registered in Windows!
echo When you click 'Play' on retro-blox.vercel.app, the RetroBlox launcher
echo will download and stream Godot games straight into RAM!
echo.
pause
