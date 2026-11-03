@echo off
SET EXE_PATH=%~dp0RetroBloxPlayer.exe
reg add "HKCU\Software\Classes\retroblox" /ve /d "URL:RetroBlox Protocol" /f
reg add "HKCU\Software\Classes\retroblox" /v "URL Protocol" /d "" /f
reg add "HKCU\Software\Classes\retroblox\shell\open\command" /ve /d "\"%EXE_PATH%\" \"%%1\"" /f
echo Registered retroblox:// protocol handler for %EXE_PATH%
