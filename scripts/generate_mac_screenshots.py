#!/usr/bin/env python3
"""Generate Mac App Store screenshots with branded treatment.

Each screenshot:
  - 2880x1800 canvas (Mac App Store dimension)
  - Dark gradient background using brand accent
  - Mac window frame around the source screenshot
  - Headline text above the window
"""

import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


# Brand colors (from codebase: sRGB 0.56, 0.65, 1.0 in dark mode)
BRAND_BLUE = (142, 165, 255)       # #8EA5FF
BG_DARK    = (18, 20, 30)         # deep navy-black
BG_MID     = (28, 32, 48)         # slightly lighter for gradient
WINDOW_BG  = (30, 33, 48)         # macOS window bg
TITLEBAR   = (45, 49, 66)         # titlebar color

SF_BLACK = "/Library/Fonts/SF-Pro-Display-Black.otf"
SF_BOLD  = "/Library/Fonts/SF-Pro-Display-Bold.otf"


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except (OSError, IOError):
        return ImageFont.load_default()


def draw_gradient(draw, w, h, top_color, bottom_color):
    for y in range(h):
        ratio = y / max(h - 1, 1)
        r = int(top_color[0] + (bottom_color[0] - top_color[0]) * ratio)
        g = int(top_color[1] + (bottom_color[1] - top_color[1]) * ratio)
        b = int(top_color[2] + (bottom_color[2] - top_color[2]) * ratio)
        draw.line([(0, y), (w, y)], fill=(r, g, b))


def draw_mac_window(draw, x, y, w, h, titlebar_text=""):
    """Draw a macOS-style window frame."""
    # Window shadow
    shadow = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([0, 0, w + 39, h + 39], radius=14, fill=(0, 0, 0, 60))
    # We'll composite later; for now just draw the window itself

    # Window background
    draw.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius=12, fill=WINDOW_BG)
    # Titlebar
    draw.rounded_rectangle([x, y, x + w - 1, y + 50 - 1], radius=12, fill=TITLEBAR)
    # Remove bottom part of titlebar that overlaps window body
    draw.rectangle([x, y + 38, x + w - 1, y + 50], fill=WINDOW_BG)

    # Traffic lights
    cx = x + 24
    cy = y + 25
    colors = [(95, 95, 95), (95, 95, 95), (95, 95, 95)]
    for i, col in enumerate(colors):
        draw.ellipse([cx + i * 20 - 5, cy - 5, cx + i * 20 + 5, cy + 5], fill=col)

    # Titlebar text (centered)
    if titlebar_text:
        try:
            tf = font(SF_BOLD, 13)
            bbox = draw.textbbox((0, 0), titlebar_text, font=tf)
            tw = bbox[2] - bbox[0]
            tx = x + (w - tw) // 2
            ty = y + 18
            draw.text((tx, ty), titlebar_text, fill=(180, 180, 190), font=tf)
        except Exception:
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshot", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--verb", required=True, help="Large headline verb (ALL CAPS)")
    parser.add_argument("--desc", required=True, help="Smaller benefit description")
    parser.add_argument("--window-title", default="CloudBridge")
    parser.add_argument("--canvas-w", type=int, default=2880)
    parser.add_argument("--canvas-h", type=int, default=1800)
    args = parser.parse_args()

    # Build canvas
    canvas = Image.new("RGB", (args.canvas_w, args.canvas_h), BG_DARK)
    draw = ImageDraw.Draw(canvas)
    draw_gradient(draw, args.canvas_w, args.canvas_h, BG_DARK, BG_MID)

    # Subtle brand glow behind window
    glow = Image.new("RGBA", (args.canvas_w, args.canvas_h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    # Soft blue glow in center area
    for r in range(900, 0, -10):
        alpha = int(18 * (1 - r / 900))
        gd.ellipse([1440 - r, 1000 - r, 1440 + r, 1000 + r], fill=(BRAND_BLUE[0], BRAND_BLUE[1], BRAND_BLUE[2], alpha))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), glow).convert("RGB")
    draw = ImageDraw.Draw(canvas)

    # Headline text
    verb_font = font(SF_BLACK, 160)
    desc_font = font(SF_BOLD, 52)

    # Measure verb
    v_bbox = draw.textbbox((0, 0), args.verb.upper(), font=verb_font)
    v_w = v_bbox[2] - v_bbox[0]
    vx = (args.canvas_w - v_w) // 2
    vy = 80
    draw.text((vx, vy), args.verb.upper(), fill=(255, 255, 255), font=verb_font)

    # Measure and wrap desc
    max_desc_w = int(args.canvas_w * 0.65)
    words = args.desc.split()
    lines = []
    current = ""
    for word in words:
        trial = f"{current} {word}".strip()
        tb = draw.textbbox((0, 0), trial, font=desc_font)
        tw = tb[2] - tb[0]
        if tw <= max_desc_w:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    if not lines:
        lines = [args.desc]

    dy = vy + (v_bbox[3] - v_bbox[1]) + 24
    for line in lines:
        db = draw.textbbox((0, 0), line, font=desc_font)
        dw = db[2] - db[0]
        dx = (args.canvas_w - dw) // 2
        draw.text((dx, dy), line, fill=BRAND_BLUE, font=desc_font)
        dy += (db[3] - db[1]) + 12

    # Source screenshot
    src = Image.open(args.screenshot).convert("RGB")
    sw, sh = src.size

    # Window area: below text, centered
    window_top = dy + 60
    window_w = int(args.canvas_w * 0.82)
    window_h = int((args.canvas_h - window_top - 40) * 0.92)
    window_x = (args.canvas_w - window_w) // 2
    window_y = window_top + 20

    draw_mac_window(draw, window_x, window_y, window_w, window_h, args.window_title)

    # Fit screenshot into window content area (below titlebar ~50px)
    content_x = window_x + 16
    content_y = window_y + 56
    content_w = window_w - 32
    content_h = window_h - 64

    # Resize source to fit content area (cover, center-top)
    src_ratio = sw / sh
    cont_ratio = content_w / content_h
    if src_ratio > cont_ratio:
        # Source wider — height matches, crop width
        new_h = content_h
        new_w = int(new_h * src_ratio)
        src_resized = src.resize((new_w, new_h), Image.Resampling.LANCZOS)
        crop_x = (new_w - content_w) // 2
        src_cropped = src_resized.crop((crop_x, 0, crop_x + content_w, new_h))
    else:
        # Source taller — width matches
        new_w = content_w
        new_h = int(new_w / src_ratio)
        src_resized = src.resize((new_w, new_h), Image.Resampling.LANCZOS)
        crop_y = 0  # top-align
        src_cropped = src_resized.crop((0, crop_y, new_w, crop_y + content_h))

    canvas.paste(src_cropped, (content_x, content_y))

    # Save
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, "PNG")
    print(f"{out} {canvas.size[0]}x{canvas.size[1]}")


if __name__ == "__main__":
    main()
