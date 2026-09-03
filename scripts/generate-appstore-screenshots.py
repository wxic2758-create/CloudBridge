from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path("AppStoreScreenshots")
OUT.mkdir(exist_ok=True)

W, H = 2880, 1800


def font(size, bold=False):
    names = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Helvetica.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


F_TITLE = font(96, True)
F_H1 = font(54, True)
F_H2 = font(42, True)
F_BODY = font(34)
F_SMALL = font(28)
F_MONO = font(30)


def rounded(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def text(draw, xy, value, fill="#16202a", f=F_BODY):
    draw.text(xy, value, fill=fill, font=f)


def button(draw, box, label, icon, fill="#1f6feb", fg="white"):
    rounded(draw, box, 18, fill)
    x, y, x2, y2 = box
    if icon and len(icon) <= 2:
        text(draw, (x + 34, y + 21), icon, fg, F_SMALL)
        text(draw, (x + 82, y + 17), label, fg, F_SMALL)
    else:
        text(draw, (x + 34, y + 17), label, fg, F_SMALL)


def base(title, subtitle):
    img = Image.new("RGB", (W, H), "#f7fbff")
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, W, 420), fill="#06162e")
    draw.rectangle((0, 420, W, H), fill="#f4f9fc")
    text(draw, (150, 115), title, "#d2f2ff", F_TITLE)
    text(draw, (155, 242), subtitle, "#8fdcff", F_H1)
    rounded(draw, (210, 500, 2670, 1635), 26, "#ffffff", "#d8e8ef", 2)
    return img, draw


def sidebar(draw):
    rounded(draw, (260, 560, 820, 1575), 18, "#06162e", "#1ca8f0", 2)
    text(draw, (320, 635), "CloudBridge", "#d2f2ff", F_H1)
    text(draw, (322, 710), "Ready", "#8fdcff", F_SMALL)
    labels = ["Server IP or domain", "Username", "Port", "Password", "Remote path"]
    y = 820
    for label in labels:
        text(draw, (320, y), label, "#8fdcff", font(23))
        rounded(draw, (320, y + 36, 760, y + 92), 10, "#102c4f", "#226b9a", 2)
        y += 112
    button(draw, (320, 1410, 760, 1480), "Connect", "bolt", "#1ca8f0")
    rounded(draw, (320, 1502, 760, 1550), 10, "#102c4f", "#226b9a", 2)
    text(draw, (350, 1512), "Downloads", "#d2f2ff", font(24))


def screenshot_connection():
    img, draw = base("CloudBridge", "A clean SFTP browser for your own servers")
    sidebar(draw)
    text(draw, (950, 620), "Only the fields you need", "#16202a", F_H1)
    text(draw, (955, 705), "Enter a host, port, username, password, and remote path to start browsing over SFTP.", "#4d6370", F_BODY)
    samples = [
        ("Server", "example.server.com"),
        ("Port", "22"),
        ("Username", "deploy"),
        ("Remote path", "/var/www/app"),
    ]
    y = 850
    for key, value in samples:
        rounded(draw, (970, y, 2410, y + 110), 18, "#f7faf8", "#dae3df", 2)
        text(draw, (1010, y + 24), key, "#6b7a75", F_SMALL)
        text(draw, (1320, y + 22), value, "#16202a", F_BODY)
        y += 150
    img.save(OUT / "01-connect.png")


def screenshot_servers():
    img, draw = base("Minimal MVP", "No saved server list, no extra setup screens")
    sidebar(draw)
    text(draw, (950, 620), "Session-only password cache", "#16202a", F_H1)
    items = [
        ("No developer account", "Connect directly to servers you control."),
        ("No persistent passwords", "The entered password stays only in the current app session."),
        ("No analytics or ads", "CloudBridge has no developer-operated backend."),
    ]
    y = 760
    for index, (name, detail) in enumerate(items):
        fill = "#edf8fd" if index == 0 else "#ffffff"
        rounded(draw, (960, y, 2470, y + 155), 20, fill, "#d8e2de", 2)
        text(draw, (1015, y + 32), name, "#16202a", F_H2)
        text(draw, (1017, y + 92), detail, "#637987", F_SMALL)
        y += 190
    button(draw, (960, 1395, 1265, 1465), "Connect", "bolt", "#1ca8f0")
    img.save(OUT / "02-saved-servers.png")


def screenshot_browser():
    img, draw = base("Browse Remote Files", "Preview, download, and move through folders")
    sidebar(draw)
    text(draw, (950, 610), "/var/www/app", "#16202a", F_H1)
    button(draw, (950, 700, 1175, 770), "Refresh", "sync", "#1086c4")
    button(draw, (1200, 700, 1455, 770), "Download", "down", "#1ca8f0")
    columns = [("Name", 950), ("Size", 1670), ("Modified", 1940)]
    for name, x in columns:
        text(draw, (x, 865), name, "#60706a", F_SMALL)
    rows = [
        ("assets", "-", "Today 11:42"),
        ("config", "-", "Yesterday 18:05"),
        ("index.html", "28 KB", "Today 12:18"),
        ("release.tar.gz", "146 MB", "Jul 4, 2026"),
        ("server.log", "2.4 MB", "Today 12:24"),
    ]
    y = 930
    for i, row in enumerate(rows):
        fill = "#f7faf8" if i % 2 == 0 else "#ffffff"
        rounded(draw, (930, y, 2500, y + 100), 12, fill, "#e3e9e6", 1)
        text(draw, (970, y + 29), row[0], "#16202a", F_BODY)
        text(draw, (1670, y + 29), row[1], "#16202a", F_BODY)
        text(draw, (1940, y + 29), row[2], "#16202a", F_BODY)
        y += 112
    img.save(OUT / "03-browser.png")


def screenshot_preview():
    img, draw = base("Quick Look Preview", "Double-click files to preview before downloading")
    sidebar(draw)
    rounded(draw, (965, 620, 2465, 1480), 24, "#06162e", "#d9e0dd", 2)
    rounded(draw, (1015, 675, 2415, 780), 16, "#102c4f")
    text(draw, (1060, 703), "server.log", "#d2f2ff", F_H2)
    log_lines = [
        "2026-07-05 00:04:18  INFO  Starting deploy",
        "2026-07-05 00:04:21  INFO  Upload complete",
        "2026-07-05 00:04:23  INFO  Reloading service",
        "2026-07-05 00:04:25  OK    Health check passed",
    ]
    y = 880
    for line in log_lines:
        text(draw, (1070, y), line, "#d2f2ff", F_MONO)
        y += 82
    button(draw, (1070, 1315, 1335, 1385), "Download", "down", "#1ca8f0")
    img.save(OUT / "04-preview.png")


if __name__ == "__main__":
    screenshot_connection()
    screenshot_servers()
    screenshot_browser()
    screenshot_preview()
    print("Generated screenshots in AppStoreScreenshots")
