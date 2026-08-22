"""Renders the DosiCrew app icon.

A drop — the dose — with a check cut out of it: one dose, confirmed once.
Drawn at 4x and downsampled, because Pillow has no antialiasing of its own.
"""
import math, os
from PIL import Image, ImageDraw

SIZE = 1024
SS = 4                      # supersampling factor
S = SIZE * SS

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient(top, bottom):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        # Slight ease so the middle band does not look like a flat stripe.
        t = y / (S - 1)
        t = t * t * (3 - 2 * t)
        d.line([(0, y), (S, y)], fill=lerp(top, bottom, t))
    return img

def drop_polygon(cx, cy, r, h, steps=720):
    """Teardrop: apex at (cx, cy-h), tangent to the circle of radius r at (cx, cy)."""
    gamma = math.acos(r / h)
    t_plus = math.atan2(-math.cos(gamma), math.sin(gamma))
    t_minus = math.atan2(-math.cos(gamma), -math.sin(gamma))
    sweep = (t_minus - t_plus) % (2 * math.pi)   # increasing angle passes the bottom
    pts = [(cx, cy - h)]
    for i in range(steps + 1):
        a = t_plus + sweep * i / steps
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

def stroke(draw, points, width, colour):
    """Polyline with round caps and joints."""
    draw.line(points, fill=colour, width=width, joint="curve")
    for x, y in points:
        draw.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=colour)

def render(top, bottom, drop_colour, mark_colour):
    img = gradient(top, bottom)
    d = ImageDraw.Draw(img)

    # Drop: circle centred a little below the middle, apex reaching up.
    r = S * 0.272
    cx, cy = S / 2, S * 0.578
    h = S * 0.392
    d.polygon(drop_polygon(cx, cy, r, h), fill=drop_colour)

    # Check, sized against the circle so it always sits inside it.
    w = r * 0.235
    pts = [
        (cx - r * 0.50, cy + r * 0.02),
        (cx - r * 0.15, cy + r * 0.38),
        (cx + r * 0.53, cy - r * 0.40),
    ]
    stroke(d, pts, int(w), mark_colour)

    return img.resize((SIZE, SIZE), Image.LANCZOS)

VARIANTS = {
    "AppIcon.png":        ((0x46, 0xCB, 0xB8), (0x16, 0x74, 0x92), (0xFF, 0xFF, 0xFF), (0x15, 0x6E, 0x8A)),
    "AppIcon-Dark.png":   ((0x1E, 0x6E, 0x80), (0x08, 0x2A, 0x36), (0xEC, 0xF7, 0xF8), (0x14, 0x4B, 0x5A)),
    "AppIcon-Tinted.png": ((0xE2, 0xE2, 0xE2), (0x6E, 0x6E, 0x6E), (0xFF, 0xFF, 0xFF), (0x54, 0x54, 0x54)),
}

out_dir = "DosiCrew/Resources/Assets.xcassets/AppIcon.appiconset"
os.makedirs(out_dir, exist_ok=True)
for name, (top, bottom, drop, mark) in VARIANTS.items():
    img = render(top, bottom, drop, mark)
    path = os.path.join(out_dir, name)
    img.save(path, "PNG")
    print(f"{path}  {img.size[0]}x{img.size[1]}  mode={img.mode}  {os.path.getsize(path)//1024} KB")
