#!/usr/bin/env python3
"""Draws Steam achievement icons in the house style (256x256 casino chip on green felt, cream
lettering in Luckiest Guy with a dark red drop shadow; a grey copy for the locked state).

Usage: python3 tools/steam/make_achievement_icons.py [OUT_DIR]   (default docs/steam/achievements)
Writes <ID>_ACHIEVED.png and <ID>_UNACHIEVED.png for every id in LABELS. Needs Pillow.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = os.path.join(ROOT, "assets", "fonts", "LuckiestGuy-Regular.ttf")
SIZE = 256
SS = 4  # supersampling

# id -> (small top line or "", big line)
LABELS = {
    "ACH_BJ_NATURAL": ("BLACK", "JACK"),
    "ACH_BJ_COLD_STREAK": ("LOSE", "x4"),
    "ACH_BJ_GREEDY": ("HIT ON", "20"),
    "ACH_BJ_FIVE_CARDS": ("5 CARD", "TRICK"),
    "ACH_ROULETTE_NUMBER": ("", "35:1"),
    "ACH_ROULETTE_PSYCHIC": ("35:1", "x2"),
    "ACH_ROULETTE_ZERO": ("", "0"),
    "ACH_SLOTS_SEVENS": ("LUCKY", "7s"),
    "ACH_PLINKO_EDGE": ("PLINKO", "10x"),
    "ACH_HILO_LADDER": ("HI-LO", "x5"),
    "ACH_WHEEL_WILD": ("", "WILD"),
    "ACH_HOLDEM_FULL_HOUSE": ("FULL", "HOUSE"),
    "ACH_ON_TILT": ("", "TILT"),
    "ACH_OUCH": ("", "OUCH"),
    "ACH_JAILBIRD": ("JAIL", "x3"),
    "ACH_WET_FLOOR": ("WET", "FLOOR"),
    "ACH_TRIP_WAITER": ("", "OOPS"),
    "ACH_HOT_POTATO": ("", "BOOM"),
    "ACH_BACKSTABBER": ("", "STEAL"),
    "ACH_COUNTERFEIT": ("FAKE", "$$$"),
    "ACH_YEET": ("", "YEET"),
    "ACH_LAST_PLACE": ("", "LAST"),
}

ON = {
    "bg_in": (40, 97, 65), "bg_out": (30, 81, 56), "rim": (22, 85, 54), "gold": (224, 181, 75),
    "red": (120, 30, 36), "spot": (250, 238, 210), "text": (250, 238, 210), "shadow": (60, 20, 20),
}
OFF = {
    "bg_in": (60, 60, 60), "bg_out": (50, 50, 50), "rim": (40, 40, 40), "gold": (142, 142, 142),
    "red": (70, 70, 70), "spot": (190, 190, 190), "text": (200, 200, 200), "shadow": (40, 40, 40),
}


def _circle(d, cx, cy, r, fill):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def _text_line(d, text, size, cy, pal, max_w):
    s = size
    while True:
        font = ImageFont.truetype(FONT, s)
        x0, y0, x1, y1 = d.textbbox((0, 0), text, font=font)
        if x1 - x0 <= max_w or s <= 8 * SS:
            break
        s -= SS
    w, h = x1 - x0, y1 - y0
    x = SIZE * SS / 2 - w / 2 - x0
    y = cy - h / 2 - y0
    off = 3 * SS
    d.text((x + off, y + off), text, font=font, fill=pal["shadow"])
    d.text((x, y), text, font=font, fill=pal["text"])


def draw(top, big, pal):
    n = SIZE * SS
    c = n / 2
    img = Image.new("RGB", (n, n), pal["bg_out"])
    d = ImageDraw.Draw(img)
    # Felt: a soft radial light in the middle.
    steps = 40
    for i in range(steps):
        t = i / (steps - 1)
        r = n * 0.75 * (1 - t)
        col = tuple(int(pal["bg_out"][k] + (pal["bg_in"][k] - pal["bg_out"][k]) * t) for k in range(3))
        _circle(d, c, c, r, col)
    _circle(d, c, c, 108 * SS, pal["rim"])
    _circle(d, c, c, 106 * SS, pal["gold"])
    for k in range(8):
        a = math.radians(90 + 45 * k)
        _circle(d, c + math.cos(a) * 94 * SS, c - math.sin(a) * 94 * SS, 11 * SS, pal["spot"])
    _circle(d, c, c, 82 * SS, pal["red"])
    _circle(d, c, c, 77 * SS, pal["gold"])
    _circle(d, c, c, 74 * SS, pal["red"])
    if top:
        _text_line(d, top, 30 * SS, c - 22 * SS, pal, 104 * SS)
        _text_line(d, big, 50 * SS, c + 16 * SS, pal, 116 * SS)
    else:
        _text_line(d, big, 58 * SS, c, pal, 118 * SS)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "steam", "achievements")
    os.makedirs(out, exist_ok=True)
    for ach, (top, big) in LABELS.items():
        draw(top, big, ON).save(os.path.join(out, ach + "_ACHIEVED.png"), optimize=True)
        draw(top, big, OFF).save(os.path.join(out, ach + "_UNACHIEVED.png"), optimize=True)
    print("wrote %d icons to %s" % (2 * len(LABELS), out))


if __name__ == "__main__":
    main()
