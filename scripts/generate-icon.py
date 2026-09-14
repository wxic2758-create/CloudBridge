#!/usr/bin/env python3
"""Generate the CloudBridge macOS app icon in all required sizes.

The 1024x1024 source is Assets/AppIcon-Source.png, rendered from the shared
SwiftUI bridge artwork by render-brand.py. This script resizes it to every
size required by the macOS app icon asset catalog and iconset.
"""

from __future__ import annotations
import os
from pathlib import Path
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "Assets"
SOURCE_PNG = ASSET_DIR / "AppIcon-Source.png"
ICON_DOCUMENT = ASSET_DIR / "IconComposer" / "CloudBridge-Purple.icon"
ICONSET_DIR = ASSET_DIR / "CloudBridge.iconset"
XCASSETS_DIR = ASSET_DIR / "Assets.xcassets"
APPICON_DIR = XCASSETS_DIR / "AppIcon.appiconset"

SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

CONTENTS_JSON = """{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def main() -> None:
    if not ICON_DOCUMENT.is_dir():
        raise FileNotFoundError(f"Icon Composer document not found: {ICON_DOCUMENT}")

    # Icon Composer is the canonical renderer for the supplied .icon document.
    # Keep the raster files checked into the project so Xcode and SwiftPM builds
    # do not need to understand the .icon format themselves.
    icon_tool = os.environ.get("ICTOOL")
    if icon_tool is None:
        developer_dir = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
        icon_tool = str(developer_dir.parent / "Applications/Icon Composer.app/Contents/Executables/ictool")
    if not Path(icon_tool).is_file():
        raise FileNotFoundError(f"Icon Composer renderer not found: {icon_tool}")
    SOURCE_PNG.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            icon_tool,
            str(ICON_DOCUMENT),
            "--export-image",
            "--output-file",
            str(SOURCE_PNG),
            "--platform",
            "macOS",
            "--rendition",
            "Default",
            "--width",
            "1024",
            "--height",
            "1024",
            "--scale",
            "1",
        ],
        check=True,
    )

    ICONSET_DIR.mkdir(parents=True, exist_ok=True)
    APPICON_DIR.mkdir(parents=True, exist_ok=True)
    (XCASSETS_DIR / "Contents.json").write_text(
        '{"info":{"author":"xcode","version":1}}\n'
    )

    source = Image.open(SOURCE_PNG).convert("RGBA")
    if source.size != (1024, 1024):
        source = source.resize((1024, 1024), Image.Resampling.LANCZOS)

    for filename, size in SIZES.items():
        icon = source.resize((size, size), Image.Resampling.LANCZOS)
        icon.save(ICONSET_DIR / filename)
        icon.save(APPICON_DIR / filename)

    (APPICON_DIR / "Contents.json").write_text(CONTENTS_JSON)


if __name__ == "__main__":
    main()
