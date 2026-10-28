#!/usr/bin/env python3
"""Read one 8-bit non-interlaced PNG pixel without external image libraries.

Usage: png-pixel.py IMAGE X Y
Prints: R G B
"""
import struct
import sys
import zlib


def paeth(a, b, c):
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_pixel(path, x, y):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    pos = 8
    width = height = None
    bit_depth = color_type = interlace = None
    idat = bytearray()
    while pos + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, bit_depth, color_type, comp, filt, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.extend(body)
        elif kind == b"IEND":
            break
    if width is None:
        raise SystemExit(f"{path}: missing IHDR")
    if bit_depth != 8 or color_type not in (2, 6) or interlace != 0:
        raise SystemExit(
            f"{path}: unsupported PNG (depth={bit_depth}, color={color_type}, interlace={interlace})"
        )
    if not (0 <= x < width and 0 <= y < height):
        raise SystemExit(f"{path}: pixel {x},{y} outside {width}x{height}")
    bpp = 4 if color_type == 6 else 3
    stride = width * bpp
    raw = zlib.decompress(bytes(idat))
    if len(raw) != (stride + 1) * height:
        raise SystemExit(f"{path}: unexpected decompressed size")
    prev = bytearray(stride)
    rows = []
    offset = 0
    for row in range(height):
        filter_type = raw[offset]
        offset += 1
        line = bytearray(raw[offset:offset + stride])
        offset += stride
        for i in range(stride):
            left = line[i - bpp] if i >= bpp else 0
            up = prev[i]
            up_left = prev[i - bpp] if i >= bpp else 0
            if filter_type == 0:
                value = line[i]
            elif filter_type == 1:
                value = line[i] + left
            elif filter_type == 2:
                value = line[i] + up
            elif filter_type == 3:
                value = line[i] + (left + up) // 2
            elif filter_type == 4:
                value = line[i] + paeth(left, up, up_left)
            else:
                raise SystemExit(f"{path}: unknown filter {filter_type}")
            line[i] = value & 0xFF
        rows.append(line)
        prev = line
    pixel = rows[y][x * bpp:(x + 1) * bpp]
    return pixel[0], pixel[1], pixel[2]


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    r, g, b = read_pixel(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]))
    print(f"{r} {g} {b}")


if __name__ == "__main__":
    main()
