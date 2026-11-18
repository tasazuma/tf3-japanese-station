#!/usr/bin/env python3
"""Generates 8-bit greyscale material-index TGAs used by the .gtex.lua ground textures."""
import struct, os

OUT = os.path.join(os.path.dirname(__file__), "..", "jpst_station", "content", "stations", "jpst", "mat")

def write_tga(path, w, h, px):
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 3, 0, 0, 0, 0, 0, w, h, 8, 0x20)
    with open(path, "wb") as f:
        f.write(hdr)
        f.write(bytes(px))

# Platform floor: 8x8 tiles of 8 px (tile = 1 m with texSize 4 m); grout lines and a yellow block per tile.
BASE, GROUT, YELLOW = 255, 128, 64
N = 32
px = []
for y in range(N):
    for x in range(N):
        tx, ty = x % 8, y % 8
        if tx == 0 or ty == 0:
            v = GROUT
        elif 3 <= tx <= 4 and 3 <= ty <= 4:
            v = YELLOW
        else:
            v = BASE
        px.append(v)
os.makedirs(OUT, exist_ok=True)
write_tga(os.path.join(OUT, "platform_floor.tga"), N, N, px)
