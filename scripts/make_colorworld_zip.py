#!/usr/bin/env python3
"""Build public/godot/colorworld-godot-game.zip from public/godot/ColorWorld.
Packaging: The zip contains one top-level folder 'ColorWorld/' so when users
unzip it, they can open the ColorWorld folder directly in Godot Engine."""
import os
import zipfile
import shutil
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
ROOT = str(BASE_DIR / "public" / "godot" / "ColorWorld")
OUT_GAME = str(BASE_DIR / "public" / "godot" / "colorworld-godot-game.zip")
OUT_SDK = str(BASE_DIR / "public" / "godot" / "colorworld-godot-sdk.zip")
TOP = "ColorWorld"

SKIP_DIRS = {".godot", "__pycache__"}
SKIP_FILES = {".DS_Store"}

def build_zip(out_path: str) -> None:
    if os.path.exists(out_path):
        os.remove(out_path)
    count = 0
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as zf:
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
    print(f"wrote {out_path}: {count} files, {os.path.getsize(out_path)} bytes")

def main() -> None:
    build_zip(OUT_GAME)
    # Also write colorworld-godot-sdk.zip for backwards compatibility
    shutil.copyfile(OUT_GAME, OUT_SDK)
    print(f"copied to {OUT_SDK}")

if __name__ == "__main__":
    main()
