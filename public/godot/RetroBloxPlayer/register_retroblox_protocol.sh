#!/usr/bin/env bash
mkdir -p ~/.local/share/applications
cat <<DESKTOP > ~/.local/share/applications/retroblox-protocol.desktop
[Desktop Entry]
Name=RetroBlox Launcher
Exec=$(pwd)/RetroBloxPlayer %u
Type=Application
Terminal=false
MimeType=x-scheme-handler/retroblox;
DESKTOP
xdg-mime default retroblox-protocol.desktop x-scheme-handler/retroblox 2>/dev/null || true
echo "Registered retroblox:// protocol handler!"
