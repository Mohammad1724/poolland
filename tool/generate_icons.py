#!/usr/bin/env python3
"""Generate all Poolland launcher icons from the approved master artwork.

Usage:
    python3 tool/generate_icons.py

The square artwork in design/icon-source.png is center-cropped to its safe,
recognizable mark and exported for Android, web/PWA, and documentation.
Adaptive Android icons get a transparent foreground with the dark canvas
removed, while their background uses a color sampled from the artwork.

Requires Pillow: python3 -m pip install Pillow
"""

from __future__ import annotations

import os
import re
from typing import TypeAlias

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "design", "icon-source.png")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

RGBAImage: TypeAlias = Image.Image
MASTER_SIZE = 1024
ARTWORK_CROP_RATIO = 0.68
CORNER_RADIUS_RATIO = 0.235


def sample_background(image: RGBAImage) -> tuple[int, int, int]:
    """Estimate the canvas color from small patches in the four corners."""
    width, height = image.size
    patch_size = max(8, min(width, height) // 32)
    origins = (
        (0, 0),
        (width - patch_size, 0),
        (0, height - patch_size),
        (width - patch_size, height - patch_size),
    )
    means = [
        ImageStat.Stat(
            image.crop((x, y, x + patch_size, y + patch_size)).convert("RGB")
        ).mean[:3]
        for x, y in origins
    ]
    return tuple(
        round(sum(color[channel] for color in means) / len(means))
        for channel in range(3)
    )


def load_master() -> tuple[RGBAImage, tuple[int, int, int]]:
    if not os.path.isfile(SOURCE):
        raise FileNotFoundError(f"Approved master icon not found: {SOURCE}")

    with Image.open(SOURCE) as opened:
        square = ImageOps.fit(
            opened.convert("RGBA"),
            (min(opened.size), min(opened.size)),
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.5),
        )
        crop_size = round(MASTER_SIZE * ARTWORK_CROP_RATIO)
        left = (square.width - crop_size) // 2
        top = (square.height - crop_size) // 2
        crop = square.crop((left, top, left + crop_size, top + crop_size))
        image = ImageOps.fit(
            crop,
            (MASTER_SIZE, MASTER_SIZE),
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.5),
        )

    background = sample_background(image)
    # Flatten any transparent source pixels onto the sampled canvas color.
    matte = Image.new("RGBA", image.size, background + (255,))
    image = Image.alpha_composite(matte, image)
    return image, background


def save(image: RGBAImage, path: str, size: int, *, rounded: bool = False) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    output = image.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")

    if rounded:
        mask = Image.new("L", (size, size), 0)
        radius = round(size * CORNER_RADIUS_RATIO)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, size - 1, size - 1), radius=radius, fill=255
        )
        output.putalpha(mask)

    output.save(path, optimize=True)
    print(f"  ✓ {os.path.relpath(path, ROOT)}  {size}×{size}")


def make_adaptive_foreground(
    image: RGBAImage,
    background: tuple[int, int, int],
) -> RGBAImage:
    """Remove the dark canvas while preserving the mark and antialiased edges."""
    rgb = image.convert("RGB")
    matte = Image.new("RGB", image.size, background)
    differences = ImageChops.difference(rgb, matte).split()
    delta = ImageChops.lighter(
        ImageChops.lighter(differences[0], differences[1]), differences[2]
    )

    # Ignore the artwork's subtle background grain, then soften the edges into
    # transparency. The near-black book seam blends into the Android background.
    low, high = 42, 92
    alpha = delta.point(
        lambda value: max(0, min(255, round((value - low) * 255 / (high - low))))
    )
    alpha = alpha.filter(ImageFilter.MedianFilter(size=3))
    alpha = ImageChops.multiply(alpha, image.getchannel("A"))
    foreground = image.copy()
    foreground.putalpha(alpha)
    return foreground


def update_adaptive_background(color: tuple[int, int, int]) -> None:
    path = os.path.join(RES, "values", "colors.xml")
    with open(path, encoding="utf-8") as file:
        contents = file.read()

    rgb_hex = "#" + "".join(f"{channel:02X}" for channel in color)
    pattern = r'(<color\s+name="ic_launcher_background">)#[0-9A-Fa-f]{6}(</color>)'
    updated, replacements = re.subn(pattern, rf"\g<1>{rgb_hex}\g<2>", contents)
    if replacements != 1:
        raise ValueError(f"Could not update the adaptive icon background in {path}")

    with open(path, "w", encoding="utf-8") as file:
        file.write(updated)
    print(f"  ✓ android adaptive background  {rgb_hex}")


def main() -> None:
    icon, background = load_master()
    foreground = make_adaptive_foreground(icon, background)

    # Rounded-corner raster icons are used by pre-adaptive Android launchers.
    densities = {
        "mdpi": (48, 108),
        "hdpi": (72, 162),
        "xhdpi": (96, 216),
        "xxhdpi": (144, 324),
        "xxxhdpi": (192, 432),
    }
    for density, (launcher_size, foreground_size) in densities.items():
        save(
            icon,
            os.path.join(RES, f"mipmap-{density}", "ic_launcher.png"),
            launcher_size,
            rounded=True,
        )
        save(
            foreground,
            os.path.join(RES, f"mipmap-{density}", "ic_launcher_foreground.png"),
            foreground_size,
        )

    # The larger copies are used by the README and by any in-app previews.
    save(icon, os.path.join(ROOT, "docs", "logo.png"), 512, rounded=True)
    save(icon, os.path.join(ROOT, "assets", "icon", "icon.png"), 512, rounded=True)

    # PWA maskable icons stay full bleed; the artwork is inside the safe zone.
    web = os.path.join(ROOT, "web", "icons")
    save(icon, os.path.join(web, "Icon-192.png"), 192)
    save(icon, os.path.join(web, "Icon-512.png"), 512)
    save(icon, os.path.join(web, "Icon-maskable-192.png"), 192)
    save(icon, os.path.join(web, "Icon-maskable-512.png"), 512)
    save(icon, os.path.join(web, "favicon.png"), 64)
    save(icon, os.path.join(ROOT, "web", "favicon.png"), 64)

    update_adaptive_background(background)
    print("\nAll Poolland icons generated successfully.")


if __name__ == "__main__":
    main()
