"""One-off script: process design/assets/icon/home/ into assets/icon/home/.

Removes background, crops to content, preserves original icon colors,
and scales to uniform square PNGs using nearest-neighbor to keep pixel-art crisp.

Usage:
    python tool/process_home_icons.py
"""
from __future__ import annotations

import shutil
import sys
from collections import Counter
from pathlib import Path

from PIL import Image

SOURCE_ROOT = Path(r"E:\AI\ai食谱\design\assets\icon\home")
OUTPUT_ROOT = Path(r"E:\AI\ai食谱\code\apps\mobile\assets\icon\home")

BG_TOLERANCE = 36
TARGET_SIZE = 64


def color_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> int:
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


def estimate_background(src: Image.Image) -> tuple[int, int, int]:
    """Sample four corners and return the most common RGB."""
    w, h = src.size
    samples = [
        src.getpixel((0, 0))[:3],
        src.getpixel((w - 1, 0))[:3],
        src.getpixel((0, h - 1))[:3],
        src.getpixel((w - 1, h - 1))[:3],
    ]
    return Counter(samples).most_common(1)[0][0]


def process_icon(src_path: Path, dst_path: Path, size: int) -> None:
    src = Image.open(src_path).convert("RGBA")
    bg = estimate_background(src)
    pixels = src.load()
    assert pixels is not None

    # Remove background but preserve original icon colors.
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = pixels[x, y]
            if a == 0 or color_distance((r, g, b), bg) <= BG_TOLERANCE * BG_TOLERANCE:
                pixels[x, y] = (0, 0, 0, 0)

    # Crop to content bounding box.
    bbox = src.getbbox()
    if bbox is None:
        cropped = src
    else:
        cropped = src.crop(bbox)

    # Scale into a square, preserving aspect ratio, nearest-neighbor.
    cropped.thumbnail((size, size), Image.Resampling.NEAREST)
    dst = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dx = (size - cropped.width) // 2
    dy = (size - cropped.height) // 2
    dst.paste(cropped, (dx, dy), cropped)

    dst.save(dst_path, "PNG")


def process_directory(src: Path, dst: Path, size: int) -> None:
    dst.mkdir(parents=True, exist_ok=True)
    for file in sorted(src.glob("*.png")):
        out = dst / file.name
        process_icon(file, out, size)
        print(f"Processed: {out}")


def process_nav_sprite(src: Path, dst: Path, size: int) -> None:
    dst.mkdir(parents=True, exist_ok=True)
    nav = Image.open(src).convert("RGBA")
    cols, rows = 4, 2
    cell_w = nav.width // cols
    cell_h = nav.height // rows
    labels = ["home", "library", "fridge", "profile"]
    states = ["inactive", "active"]

    for row in range(rows):
        for col in range(cols):
            left = col * cell_w
            upper = row * cell_h
            cell = nav.crop((left, upper, left + cell_w, upper + cell_h))
            tmp = dst / f"tmp_{row}_{col}.png"
            cell.save(tmp, "PNG")
            out = dst / f"{labels[col]}_{states[row]}.png"
            process_icon(tmp, out, size)
            tmp.unlink()
            print(f"Processed nav: {out}")


def main() -> int:
    if OUTPUT_ROOT.exists():
        shutil.rmtree(OUTPUT_ROOT)
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)

    process_directory(SOURCE_ROOT / "冰箱", OUTPUT_ROOT / "fridge", TARGET_SIZE)
    process_directory(SOURCE_ROOT / "菜品分类", OUTPUT_ROOT / "categories", TARGET_SIZE)
    process_directory(SOURCE_ROOT / "快速导图", OUTPUT_ROOT / "quick", TARGET_SIZE)
    process_nav_sprite(SOURCE_ROOT / "nav.png", OUTPUT_ROOT / "nav", TARGET_SIZE)

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
