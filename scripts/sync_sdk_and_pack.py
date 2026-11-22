#!/usr/bin/env python3
import os
import shutil
import zipfile
from pathlib import Path

SRC_SDK = Path(r"D:\Folders\RetroBlox\RetroBlox_SDK") if Path(r"D:\Folders\RetroBlox\RetroBlox_SDK").exists() else Path(r"d:\Apps\Retroblox\RetrobloxSDK")
REPO_DIR = Path(__file__).resolve().parent.parent
GODOT_PLAYER_DIR = REPO_DIR / "public" / "godot" / "RetroBloxPlayer"
SDK_ZIP_OUT = REPO_DIR / "public" / "downloads" / "RetroBlox_SDK.zip"
PLAYER_ZIP_OUT = REPO_DIR / "public" / "godot" / "retroblox-godot-player.zip"

SKIP_DIRS = {".godot", "__pycache__", ".git"}
SKIP_FILES = {".DS_Store", "test_load.gd"}

def sync_tree(src: Path, dst: Path):
    print(f"Syncing from {src} to {dst}...")
    if not dst.exists():
        dst.mkdir(parents=True, exist_ok=True)
    
    # Copy all files from src to dst excluding SKIP_DIRS
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        rel = os.path.relpath(root, src)
        target_dir = dst if rel == "." else dst / rel
        target_dir.mkdir(parents=True, exist_ok=True)
        for f in files:
            if f in SKIP_FILES or f.endswith(".tmp"):
                continue
            src_file = Path(root) / f
            dst_file = target_dir / f
            shutil.copy2(src_file, dst_file)
    print("Sync complete.")

def create_zip(src: Path, zip_path: Path):
    print(f"Packing {src} into {zip_path}...")
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    if zip_path.exists():
        zip_path.unlink()
        
    count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(src):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            rel = os.path.relpath(root, src)
            for f in sorted(files):
                if f in SKIP_FILES or f.endswith(".tmp"):
                    continue
                full_path = Path(root) / f
                arc_name = f if rel == "." else f"{rel}/{f}".replace("\\", "/")
                zf.write(full_path, arc_name)
                count += 1
                
    size_mb = zip_path.stat().st_size / (1024 * 1024)
    print(f"Packed {count} files into {zip_path} ({size_mb:.2f} MB)")

def main():
    sync_tree(SRC_SDK, GODOT_PLAYER_DIR)
    create_zip(SRC_SDK, SDK_ZIP_OUT)
    create_zip(SRC_SDK, PLAYER_ZIP_OUT)

if __name__ == "__main__":
    main()
