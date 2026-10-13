#!/usr/bin/env python3
"""Rebuild public/godot/retroblox-godot-player.zip from the live kit folder.
FLAT layout, matching every kit zip shipped so far: project.godot sits at
the zip root (no wrapper folder). Includes explicit directory entries like
the originals. Excludes Godot cache (.godot/) and OS junk."""
import os
import zipfile

ROOT = "/home/z/my-project/RetroBlox/public/godot/RetroBloxPlayer"
OUT = "/home/z/my-project/RetroBlox/public/godot/retroblox-godot-player.zip"

SKIP_DIRS = {".godot", "__pycache__"}
SKIP_FILES = {".DS_Store"}

def main() -> None:
    if os.path.exists(OUT):
        os.remove(OUT)
    count = 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as zf:
        for dirpath, dirnames, filenames in os.walk(ROOT):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            rel_dir = os.path.relpath(dirpath, ROOT)
            if rel_dir != ".":
                zf.write(dirpath, rel_dir + "/")
            for fn in sorted(filenames):
                if fn in SKIP_FILES or fn.endswith(".tmp"):
                    continue
                full = os.path.join(dirpath, fn)
                zf.write(full, os.path.relpath(full, ROOT))
                count += 1
    print(f"wrote {OUT}: {count} files, {os.path.getsize(OUT)} bytes")

if __name__ == "__main__":
    main()
