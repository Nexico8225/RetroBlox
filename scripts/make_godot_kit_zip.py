#!/usr/bin/env python3
"""Rebuild public/godot/retroblox-godot-player.zip from the live kit folder.
v4 "ROLES" layout: the zip now contains ONE top-level folder, RetroBloxPlayer/,
so "unzip -> open the RetroBloxPlayer folder in Godot" is literally true —
no more loose files dumped into your downloads directory. Includes explicit
directory entries like the originals. Excludes Godot cache (.godot/) and OS junk."""
import os
import zipfile
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
ROOT = str(BASE_DIR / "public" / "godot" / "RetroBloxPlayer")
OUT = str(BASE_DIR / "public" / "godot" / "retroblox-godot-player.zip")
TOP = "RetroBloxPlayer"  # the one folder inside the zip

SKIP_DIRS = {".godot", "__pycache__"}
SKIP_FILES = {".DS_Store"}

def main() -> None:
    if os.path.exists(OUT):
        os.remove(OUT)
    count = 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(TOP + "/", "")
        for dirpath, dirnames, filenames in os.walk(ROOT):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            rel_dir = os.path.relpath(dirpath, ROOT)
            arc_dir = TOP if rel_dir == "." else TOP + "/" + rel_dir
            if rel_dir != ".":
                zf.write(dirpath, arc_dir + "/")
            for fn in sorted(filenames):
                if fn in SKIP_FILES or fn.endswith(".tmp"):
                    continue
                full = os.path.join(dirpath, fn)
                zf.write(full, arc_dir + "/" + fn)
                count += 1
    print(f"wrote {OUT}: {count} files, {os.path.getsize(OUT)} bytes")

if __name__ == "__main__":
    main()
