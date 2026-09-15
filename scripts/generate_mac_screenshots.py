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
from PIL import Image, ImageDraw, ImageFilter, ImageFont


# Brand colors (from codebase: sRGB 0.56, 0.65, 1.0 in dark mode)
BRAND_BLUE = (142, 165, 255)       # #8EA5FF
BG_DARK    = (18, 20, 30)         # deep navy-black
BG_MID     = (28, 32, 48)         # slightly lighter for gradient
WINDOW_BG  = (30, 33, 48)         # macOS window bg
TITLEBAR   = (45, 49, 66)         # titlebar color
BRAND_PURPLE = (97, 56, 184)      # light-mode app accent
BG_LIGHT_TOP = (250, 249, 253)
BG_LIGHT_BOTTOM = (232, 227, 247)
WINDOW_LIGHT = (255, 255, 255)
TITLEBAR_LIGHT = (246, 244, 250)

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


def draw_mac_window(draw, x, y, w, h, titlebar_text="", *, window_bg=WINDOW_BG, titlebar=TITLEBAR, title_color=(180, 180, 190)):
    """Draw a macOS-style window frame."""
    # Window shadow
    shadow = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([0, 0, w + 39, h + 39], radius=14, fill=(0, 0, 0, 60))
    # We'll composite later; for now just draw the window itself

    # Window background
    draw.rounded_rectangle([x + 10, y + 18, x + w + 9, y + h + 17], radius=22, fill=(213, 207, 227))
    draw.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius=18, fill=window_bg)
    # Titlebar
    draw.rounded_rectangle([x, y, x + w - 1, y + 50 - 1], radius=18, fill=titlebar)
    # Remove bottom part of titlebar that overlaps window body
    draw.rectangle([x, y + 38, x + w - 1, y + 50], fill=window_bg)

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
            draw.text((tx, ty), titlebar_text, fill=title_color, font=tf)
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
    parser.add_argument("--light", action="store_true", help="Use the bright CloudBridge marketing palette")
    parser.add_argument("--crop-top", type=int, default=0, help="Remove capture-only pixels from the source top edge")
    parser.add_argument("--source-has-frame", action="store_true", help="Place an already-framed macOS window without drawing another frame")
    args = parser.parse_args()

    brand = BRAND_PURPLE if args.light else BRAND_BLUE
    bg_top = BG_LIGHT_TOP if args.light else BG_DARK
    bg_bottom = BG_LIGHT_BOTTOM if args.light else BG_MID
    window_bg = WINDOW_LIGHT if args.light else WINDOW_BG
    titlebar = TITLEBAR_LIGHT if args.light else TITLEBAR
    headline_color = (35, 27, 52) if args.light else (255, 255, 255)
    title_color = (96, 88, 112) if args.light else (180, 180, 190)

    # Build canvas
    canvas = Image.new("RGB", (args.canvas_w, args.canvas_h), bg_top)
    draw = ImageDraw.Draw(canvas)
    draw_gradient(draw, args.canvas_w, args.canvas_h, bg_top, bg_bottom)

    # Subtle brand glow behind window
    glow = Image.new("RGBA", (args.canvas_w, args.canvas_h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    # Soft blue glow in center area
    for r in range(900, 0, -10):
        alpha = int(18 * (1 - r / 900))
        gd.ellipse([1440 - r, 1000 - r, 1440 + r, 1000 + r], fill=(brand[0], brand[1], brand[2], alpha))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), glow).convert("RGB")
    draw = ImageDraw.Draw(canvas)

    # Headline text
    verb_font = font(SF_BLACK, 160)
    desc_font = font(SF_BOLD, 52)

    # Measure verb
    v_bbox = draw.textbbox((0, 0), args.verb, font=verb_font)
    vx = args.canvas_w // 2
    vy = 80
    draw.text((vx, vy), args.verb, fill=headline_color, font=verb_font, anchor="ma")

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

    dy = vy + v_bbox[3] + 32
    for line in lines:
        db = draw.textbbox((0, 0), line, font=desc_font)
        draw.text((args.canvas_w // 2, dy), line, fill=brand, font=desc_font, anchor="ma")
        dy += (db[3] - db[1]) + 12

    # Source screenshot
    src = Image.open(args.screenshot).convert("RGB")
    if args.crop_top > 0:
        src = src.crop((0, min(args.crop_top, src.height - 1), src.width, src.height))
    sw, sh = src.size

    # Window area: below text, centered
    window_top = dy + 60
    max_content_w = int(args.canvas_w * 0.82) - 32
    max_content_h = int((args.canvas_h - window_top - 40) * 0.94) - 64
    scale = min(max_content_w / sw, max_content_h / sh)
    content_w = int(sw * scale)
    content_h = int(sh * scale)
    window_w = content_w + (0 if args.source_has_frame else 32)
    window_h = content_h + (0 if args.source_has_frame else 64)
    window_x = (args.canvas_w - window_w) // 2
    window_y = window_top + 20

    if args.source_has_frame:
        shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        shadow_draw = ImageDraw.Draw(shadow)
        shadow_draw.rounded_rectangle(
            [window_x + 8, window_y + 14, window_x + window_w + 7, window_y + window_h + 13],
            radius=34,
            fill=(63, 39, 105, 42),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(26))
        canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
        src_resized = src.resize((content_w, content_h), Image.Resampling.LANCZOS)
        mask = Image.new("L", (content_w, content_h), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, content_w - 1, content_h - 1], radius=max(18, int(content_w * 0.018)), fill=255
        )
        canvas.paste(src_resized, (window_x, window_y), mask)
    else:
        draw_mac_window(draw, window_x, window_y, window_w, window_h, args.window_title,
                        window_bg=window_bg, titlebar=titlebar, title_color=title_color)

    # Fit screenshot into window content area (below titlebar ~50px)
    if not args.source_has_frame:
        content_x = window_x + 16
        content_y = window_y + 56
        content_w = window_w - 32
        content_h = window_h - 64
        src_resized = src.resize((content_w, content_h), Image.Resampling.LANCZOS)
        canvas.paste(src_resized, (content_x, content_y))

    # Save
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, "PNG")
    print(f"{out} {canvas.size[0]}x{canvas.size[1]}")


if __name__ == "__main__":
    main()
