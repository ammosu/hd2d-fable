#!/usr/bin/env python3
"""與第三版並排：python3 tools/cmp.py work/compare_x.png out.png [x0 y0 x1 y1]"""
import sys
from PIL import Image
a = Image.open(__import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '/../../shots/godot_diorama/r3/full_1.png'); b = Image.open(sys.argv[1])
if len(sys.argv) > 3:
    box = tuple(int(v) for v in sys.argv[3:7]); a = a.crop(box); b = b.crop(box)
    s = Image.new('RGB', (a.width, a.height * 2 + 6)); s.paste(a, (0, 0)); s.paste(b, (0, a.height + 6))
else:
    a = a.resize((960, 540)); b = b.resize((960, 540)); s = Image.new('RGB', (1926, 540)); s.paste(a, (0, 0)); s.paste(b, (966, 0))
s.save(sys.argv[2])
