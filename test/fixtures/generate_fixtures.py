"""Generates the JPEG fixtures used by test/jpeg_exif_reader_fixture_test.dart.

The images are synthetic (solid colours) and were created by this script, so no third-party
images or licences are involved. EXIF is written by Pillow, an EXIF writer independent of the
Dart reader under test. Re-run with:  python3 test/fixtures/generate_fixtures.py
"""
import io
import os
from fractions import Fraction

from PIL import Image, TiffImagePlugin

HERE = os.path.dirname(os.path.abspath(__file__))
R = TiffImagePlugin.IFDRational


def build(name, endian, size, colour, ifd0, exif_ifd, gps_ifd):
    img = Image.new("RGB", size, colour)
    exif = Image.Exif()
    exif.endian = endian
    for k, v in ifd0.items():
        exif[k] = v
    if exif_ifd:
        exif.get_ifd(0x8769).update(exif_ifd)
    if gps_ifd:
        exif.get_ifd(0x8825).update(gps_ifd)
    img.save(os.path.join(HERE, name), "JPEG", exif=exif.tobytes(), quality=85)


# Little-endian (II): Canon-like portrait shot in London, rotated 90 degrees clockwise.
build(
    "pillow_ii.jpg", "<", (64, 48), (200, 30, 30),
    ifd0={0x010F: "Canon", 0x0110: "Canon EOS 80D", 0x0112: 6, 0x0131: "fixture-gen 1.0",
          0x0132: "2024:05:06 07:08:09"},
    exif_ifd={0x9003: "2024:05:06 07:08:09", 0x9011: "+01:00", 0x9291: "250",
              0x829A: R(1, 125), 0x829D: R(28, 10), 0x8827: 400, 0x920A: R(50, 1)},
    gps_ifd={1: "N", 2: (R(51, 1), R(30, 1), R(1234, 100)),
             3: "W", 4: (R(0, 1), R(7, 1), R(3960, 100)),
             5: b"\x00", 6: R(35, 1)},
)

# Big-endian (MM): southern/eastern hemisphere, below sea level, orientation 8.
build(
    "pillow_mm.jpg", ">", (40, 30), (30, 200, 30),
    ifd0={0x010F: "NIKON CORPORATION", 0x0110: "NIKON D750", 0x0112: 8},
    exif_ifd={0x9003: "2019:12:31 23:59:58", 0x9011: "-05:30",
              0x829A: R(1, 4000), 0x829D: R(4, 1), 0x8827: 100, 0x920A: R(245, 10)},
    gps_ifd={1: "S", 2: (R(33, 1), R(52, 1), R(4800, 100)),
             3: "E", 4: (R(151, 1), R(12, 1), R(3600, 100)),
             5: b"\x01", 6: R(125, 10)},
)

# No EXIF at all.
Image.new("RGB", (8, 8), (10, 10, 10)).save(os.path.join(HERE, "no_exif.jpg"), "JPEG")

for n in ("pillow_ii.jpg", "pillow_mm.jpg"):
    with Image.open(os.path.join(HERE, n)) as im:
        e = im.getexif()
        print(n, "endian", e.endian, "orientation", e.get(0x0112), "gps", dict(e.get_ifd(0x8825)))
