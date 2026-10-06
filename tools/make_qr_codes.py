#!/usr/bin/env python3
"""Generate the 5 printable QR codes for the QR Treasure Hunt game.

Each QR encodes a NEXUS-CLUE payload the game recognizes:
    NEXUS-CLUE-<n>:<hint text for the next hiding spot>
Print them, hide them around the house, and scan in order 1..5.
Output: assets/qr_codes/qr_<n>.png (+ a qr_sheet.png contact sheet).
"""
import os
import qrcode
from qrcode.image.styledpil import StyledPilImage
from qrcode.image.styles.moduledrawers import RoundedModuleDrawer

CLUES = [
    (1, "NEXUS-CLUE-1:Look where the sun rises in the kitchen — check the window!",
     "Clue 1 — start here"),
    (2, "NEXUS-CLUE-2:The cold keeper of midnight snacks guards me. (The fridge!)",
     "Clue 2"),
    (3, "NEXUS-CLUE-3:I'm flat, I show stories, and I hang on the wall. (Behind the TV/frame!)",
     "Clue 3"),
    (4, "NEXUS-CLUE-4:Where shoes rest after a long day. (The shoe rack!)",
     "Clue 4"),
    (5, "NEXUS-CLUE-5:TREASURE! You found them all — claim your AR loot in the game!",
     "Clue 5 — TREASURE"),
]

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "assets", "qr_codes")
os.makedirs(OUT, exist_ok=True)

imgs = []
for n, payload, label in CLUES:
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,
                       box_size=12, border=4)
    qr.add_data(payload)
    qr.make(fit=True)
    img = qr.make_image(image_factory=StyledPilImage,
                        module_drawer=RoundedModuleDrawer()).convert("RGB")
    # Label banner.
    from PIL import ImageDraw, ImageFont, Image
    banner = Image.new("RGB", (img.width, 64), "white")
    d = ImageDraw.Draw(banner)
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", 28)
    except OSError:
        font = ImageFont.load_default()
    d.text((16, 14), label, fill="black", font=font)
    sheet = Image.new("RGB", (img.width, img.height + 64), "white")
    sheet.paste(banner, (0, 0))
    sheet.paste(img, (0, 64))
    path = os.path.join(OUT, f"qr_{n}.png")
    sheet.save(path)
    imgs.append(sheet)
    print("wrote", path, payload[:40] + "...")

# Contact sheet for one-page printing.
from PIL import Image
cols = 3
cw, ch = imgs[0].size
rows = (len(imgs) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cw, rows * ch), "white")
for i, im in enumerate(imgs):
    sheet.paste(im, ((i % cols) * cw, (i // cols) * ch))
sheet.save(os.path.join(OUT, "qr_sheet.png"))
print("wrote", os.path.join(OUT, "qr_sheet.png"))
