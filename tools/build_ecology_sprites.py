#!/usr/bin/env python3
"""Draw small, original pixel sprites for the live wetland layer (stdlib only)."""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1] / "assets" / "art"


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.data = bytearray(w * h * 4)

    def pixel(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.data[(y * self.w + x) * 4:(y * self.w + x) * 4 + 4] = bytes(color)

    def rect(self, x0, y0, x1, y1, color):
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.pixel(x, y, color)

    def oval(self, x0, y0, x1, y1, color):
        cx, cy = (x0 + x1 - 1) / 2, (y0 + y1 - 1) / 2
        rx, ry = max((x1 - x0) / 2, 1), max((y1 - y0) / 2, 1)
        for y in range(y0, y1):
            for x in range(x0, x1):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1:
                    self.pixel(x, y, color)

    def line(self, x0, y0, x1, y1, color, width=1):
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(steps + 1):
            x = round(x0 + (x1 - x0) * i / steps)
            y = round(y0 + (y1 - y0) * i / steps)
            self.rect(x, y, x + width, y + width, color)

    def paste(self, src, dx, dy):
        for y in range(src.h):
            for x in range(src.w):
                k = (y * src.w + x) * 4
                if src.data[k + 3]:
                    self.pixel(dx + x, dy + y, src.data[k:k + 4])

    def save(self, path):
        def chunk(tag, data):
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
        raw = b"".join(b"\0" + self.data[y * self.w * 4:(y + 1) * self.w * 4] for y in range(self.h))
        path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


INK = (35, 56, 57, 255)
WHITE = (233, 237, 217, 255)
CREAM = (248, 244, 214, 255)
BLACK = (41, 51, 55, 255)
GRAY = (154, 165, 157, 255)
RED = (194, 75, 65, 255)
ORANGE = (220, 137, 57, 255)
BROWN = (141, 111, 82, 255)

# Body, wing, beak, face, legs; all five species get every action frame.
SPECIES = [
    (CREAM, BLACK, BLACK, RED, RED),       # 白鹤
    (WHITE, BLACK, BLACK, WHITE, RED),     # 东方白鹳
    (CREAM, WHITE, BLACK, CREAM, BLACK),   # 小天鹅
    (GRAY, (202, 209, 197, 255), BLACK, RED, RED),  # 白枕鹤
    (BROWN, (191, 170, 140, 255), ORANGE, WHITE, ORANGE),  # 鸿雁
]


def bird_frame(colors, frame):
    body, wing, beak, face, legs = colors
    c = Canvas(32, 32)
    flying = frame in (5, 6, 7)
    pecking = frame in (3, 4)
    shift = 1 if frame in (2, 4, 6) else 0
    if flying:
        wing_extent = (3, 1, 5)[frame - 5]
        c.oval(8, 12, 25, 22, INK)
        c.oval(9, 13, 24, 21, body)
        c.rect(5, 15, 10, 19, wing)
        c.oval(13, wing_extent, 22, 16, INK)
        c.oval(14, wing_extent + 1, 21, 15, wing)
        c.oval(13, 18, 22, 32 - wing_extent, INK)
        c.oval(14, 19, 21, 31 - wing_extent, wing)
    else:
        # Foot and neck positions visibly change between standing, walking,
        # pecking and perching, while all frames retain a right-facing head.
        if frame != 8:
            c.line(13 + shift, 21, 12 + shift, 27, legs)
            c.line(19 - shift, 21, 20 - shift, 27, legs)
            c.rect(9 + shift, 27, 15 + shift, 29, legs)
            c.rect(18 - shift, 27, 24 - shift, 29, legs)
        else:
            c.rect(12, 21, 21, 23, legs)
        c.oval(6 + shift, 9, 24 + shift, 23, INK)
        c.oval(7 + shift, 10, 23 + shift, 22, body)
        c.oval(10 + shift, 11, 20 + shift, 20, wing)
        c.rect(4 + shift, 14, 8 + shift, 19, wing)
    head_y = 20 if pecking else 12
    if flying:
        head_y = 12
    c.rect(21 + shift, 14, 26 + shift, head_y + 4, body)
    c.oval(23 + shift, head_y, 29 + shift, head_y + 7, INK)
    c.oval(24 + shift, head_y + 1, 28 + shift, head_y + 6, face)
    c.rect(28 + shift, head_y + 3, 32, head_y + 5, beak)
    c.pixel(27 + shift, head_y + 2, BLACK)
    return c


def make_birds():
    sheet = Canvas(32 * 9, 32 * 5)
    for species, colors in enumerate(SPECIES):
        for frame in range(9):
            sheet.paste(bird_frame(colors, frame), frame * 32, species * 32)
    sheet.save(ROOT / "bird-actions.png")


def make_island():
    c = Canvas(48, 48)
    dark = (73, 67, 47, 255)
    wood = (143, 105, 62, 255)
    light = (192, 148, 83, 255)
    grass = (91, 136, 74, 255)
    reed = (196, 185, 106, 255)
    c.rect(5, 23, 43, 37, dark)
    c.rect(8, 20, 40, 34, wood)
    for y in (23, 28, 33):
        c.rect(9, y, 39, y + 2, light)
    for x in (10, 22, 34):
        c.rect(x, 21, x + 2, 35, dark)
    c.oval(12, 14, 37, 29, (65, 108, 61, 255))
    c.oval(15, 15, 35, 25, grass)
    for x, y in ((15, 14), (20, 11), (28, 10), (34, 14), (38, 17)):
        c.line(x, 20, x + 1, y, grass, 2)
        c.rect(x, y, x + 2, y + 2, reed)
    c.save(ROOT / "floating-island.png")


def make_tree():
    c = Canvas(40, 44)
    trunk = (87, 75, 49, 255)
    outline = (38, 72, 54, 255)
    deep = (48, 99, 66, 255)
    mid = (70, 127, 77, 255)
    light = (128, 160, 91, 255)
    c.rect(17, 26, 23, 43, trunk)
    c.rect(14, 33, 26, 37, trunk)
    c.oval(3, 5, 37, 35, outline)
    c.oval(5, 4, 34, 30, deep)
    c.oval(9, 3, 31, 23, mid)
    c.rect(9, 10, 15, 14, light)
    c.rect(19, 6, 28, 10, light)
    c.rect(25, 16, 32, 20, light)
    c.rect(7, 22, 13, 26, mid)
    c.save(ROOT / "shore-tree.png")


if __name__ == "__main__":
    ROOT.mkdir(parents=True, exist_ok=True)
    make_birds()
    make_island()
    make_tree()
    print("Wrote bird-actions.png, floating-island.png, shore-tree.png")
