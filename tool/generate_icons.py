#!/usr/bin/env python3
"""
Generate Poolland app icons automatically.

Usage:
    python3 tool/generate_icons.py

Outputs:
  • design/icon-source.png            main 1024×1024 icon
  • docs/logo.png                     512×512 logo for README
  • android/.../mipmap-*/ic_launcher.png            legacy Android icon
  • android/.../mipmap-*/ic_launcher_foreground.png adaptive foreground layer
  • web/icons/Icon-*.png              web icons

If you have a custom icon, place it at design/icon-source.png
and run this script to regenerate all sizes.
"""

from __future__ import annotations

import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG_TOP = (17, 30, 52)       # Dark navy
BG_BOTTOM = (11, 19, 33)
TEAL = (14, 165, 164)       # Brand teal
EMERALD = (52, 211, 153)
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_rect(size, radius_ratio=0.235):
    """Rounded-corner rectangle mask (relative to the image size)"""
    w, h = size
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    r = int(min(w, h) * radius_ratio)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return mask


def vertical_gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size)
    d = ImageDraw.Draw(img)
    for y in range(h):
        d.line([(0, y), (w, y)], fill=lerp(top, bottom, y / max(1, h - 1)))
    return img


def bezier(p0, p1, p2, steps=48):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t**2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t**2 * p2[1]
        pts.append((x, y))
    return pts


def shield_polygon(size, scale=0.62, offset_y=-0.03):
    """Shield outline: flat top, pointed bottom"""
    w, h = size
    sw = w * scale
    x0 = (w - sw) / 2
    x1 = x0 + sw
    y0 = h * (0.5 - scale / 2) + h * offset_y
    y1 = y0 + sw * 1.12
    ym = y0 + sw * 0.62
    cx = w / 2

    pts = [(x0, y0), (x1, y0)]
    pts += bezier((x1, ym), (x1 - sw * 0.06, y1 - sw * 0.22), (cx, y1))
    pts += bezier((cx, y1), (x0 + sw * 0.06, y1 - sw * 0.22), (x0, ym))
    return pts


def shield_mask(size, scale=0.62):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(shield_polygon(size, scale=scale), fill=255)
    return mask


def shield_layer(size, scale=0.62, with_bars=True):
    """Shield with a teal gradient and three ascending white bars"""
    w, h = size
    grad = Image.new("RGB", size)
    d = ImageDraw.Draw(grad)
    for y in range(h):
        d.line([(0, y), (w, y)], fill=lerp(TEAL, EMERALD, y / max(1, h - 1)))
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(grad, (0, 0), shield_mask(size, scale=scale))

    if with_bars:
        dr = ImageDraw.Draw(layer)
        sw = w * scale
        cx = w / 2
        base_y = h * 0.5 + sw * 0.16
        bar_w = sw * 0.15
        gap = sw * 0.09
        heights = [sw * 0.20, sw * 0.30, sw * 0.42]
        for i, bh in enumerate(heights):
            x = cx - (bar_w * 1.5 + gap) + i * (bar_w + gap)
            dr.rounded_rectangle(
                [x, base_y - bh, x + bar_w, base_y],
                radius=bar_w * 0.42,
                fill=WHITE + (255,),
            )
    return layer


def make_icon(size=1024, with_background=True, radius_ratio=0.235):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if with_background:
        bg = vertical_gradient((size, size), BG_TOP, BG_BOTTOM).convert("RGBA")
        img.paste(bg, (0, 0), rounded_rect((size, size), radius_ratio))
    img.alpha_composite(shield_layer((size, size), scale=0.60))
    return img


def save(img, path, size=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = img.resize((size, size), Image.LANCZOS) if size else img
    out.save(path)
    print(f"  ✓ {os.path.relpath(path, ROOT)}  {out.size[0]}×{out.size[1]}")


def main():
    icon = make_icon(1024)
    save(icon, os.path.join(ROOT, "design", "icon-source.png"))
    save(icon, os.path.join(ROOT, "docs", "logo.png"), 512)
    save(icon, os.path.join(ROOT, "assets", "icon", "icon.png"), 512)

    # Legacy Android icons and adaptive-icon foreground layers
    densities = {
        "mdpi": (48, 108),
        "hdpi": (72, 162),
        "xhdpi": (96, 216),
        "xxhdpi": (144, 324),
        "xxxhdpi": (192, 432),
    }
    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    fg_only = make_icon(1024, with_background=False)

    for name, (launcher, foreground) in densities.items():
        save(icon, os.path.join(res, f"mipmap-{name}", "ic_launcher.png"), launcher)
        save(fg_only, os.path.join(res, f"mipmap-{name}", "ic_launcher_foreground.png"), foreground)

    # web icons
    web = os.path.join(ROOT, "web", "icons")
    save(icon, os.path.join(web, "Icon-192.png"), 192)
    save(icon, os.path.join(web, "Icon-512.png"), 512)
    save(icon, os.path.join(web, "Icon-maskable-192.png"), 192)
    save(icon, os.path.join(web, "Icon-maskable-512.png"), 512)
    save(icon, os.path.join(web, "favicon.png"), 64)

    print("\nAll icons generated ✅")


if __name__ == "__main__":
    main()
