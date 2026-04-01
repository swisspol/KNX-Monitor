#!/usr/bin/env python3
"""Generate all app icon assets from a source icon.png (1024x1024).

Uses Lanczos resampling (LANCZOS) for downscaling, which is the highest quality
filter available in Pillow. Lanczos uses a windowed sinc function that preserves
sharp edges and fine detail better than bilinear or bicubic interpolation, while
minimizing aliasing artifacts. It's the standard choice for high-quality image
downscaling.

Usage:
    python generate_icons.py
"""

from pathlib import Path
from PIL import Image

SCRIPT_DIR = Path(__file__).parent
SOURCE = SCRIPT_DIR / "icon.png"

# Flutter asset for About dialog (displayed at 64x64, needs 128px for Retina)
ABOUT_ICON = SCRIPT_DIR / "assets" / "app_icon.png"
ABOUT_SIZE = 128

# macOS icon set — sizes derived from Contents.json (unique pixel sizes only)
MACOS_DIR = SCRIPT_DIR / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]

# iOS (iPad-only) icon set — sizes derived from Contents.json
IOS_DIR = SCRIPT_DIR / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

# Windows .ico — contains multiple sizes in one file
WINDOWS_ICO = SCRIPT_DIR / "windows" / "runner" / "resources" / "app_icon.ico"
WINDOWS_SIZES = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def main():
    src = Image.open(SOURCE)
    assert src.size == (1024, 1024), f"Expected 1024x1024, got {src.size}"
    assert src.mode == "RGBA", f"Expected RGBA, got {src.mode}"

    # About dialog icon
    ABOUT_ICON.parent.mkdir(parents=True, exist_ok=True)
    src.resize((ABOUT_SIZE, ABOUT_SIZE), Image.LANCZOS).save(
        ABOUT_ICON, "PNG", optimize=True
    )
    print(f"  {ABOUT_ICON} ({ABOUT_SIZE}x{ABOUT_SIZE})")

    # macOS icon set
    for size in MACOS_SIZES:
        path = MACOS_DIR / f"app_icon_{size}.png"
        if size == 1024:
            src.save(path, "PNG", optimize=True)
        else:
            src.resize((size, size), Image.LANCZOS).save(path, "PNG", optimize=True)
        print(f"  {path} ({size}x{size})")

    # iOS (iPad-only) icon set
    for filename, px in IOS_ICONS.items():
        path = IOS_DIR / filename
        if px == 1024:
            src.save(path, "PNG", optimize=True)
        else:
            src.resize((px, px), Image.LANCZOS).save(path, "PNG", optimize=True)
        print(f"  {path} ({px}x{px})")

    # Windows .ico — Pillow's ICO plugin requires passing all sizes via
    # append_images on the largest image, not the smallest.
    WINDOWS_ICO.parent.mkdir(parents=True, exist_ok=True)
    ico_images = [src.resize(s, Image.LANCZOS) for s in reversed(WINDOWS_SIZES)]
    ico_images[0].save(
        WINDOWS_ICO,
        format="ICO",
        append_images=ico_images[1:],
    )
    sizes_str = ", ".join(f"{w}x{h}" for w, h in WINDOWS_SIZES)
    print(f"  {WINDOWS_ICO} ({sizes_str})")

    print("Done.")


if __name__ == "__main__":
    main()
