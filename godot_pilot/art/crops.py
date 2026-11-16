#!/usr/bin/env python3
"""固定區域的 1:1 裁切與並排比對（每一步都用同一組座標）。
  python3 art/crops.py <shots 子資料夾> [surface]
  → <dir>/crop_ground.png crop_roof.png crop_wall.png crop_hero.png（從 full_1.png 原尺寸裁切，不縮放）
  給 surface（ground/roof/wall/hero）時另存 crop.png 與 compare.png（左 00_base｜右 本步驟，同區域 1:1）。
  surface = all → compare_base_final.png（整張 基準｜最終）＋四個表面的 compare_<s>.png"""
import os, sys
from PIL import Image
S = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'shots', 'godot_pilot')
RECT = {'ground': (560, 470, 1200, 830), 'roof': (1290, 95, 1900, 350), 'wall': (850, 70, 1280, 470), 'hero': (680, 520, 900, 740),
        'baker': (1470, 440, 1630, 620), 'child': (1400, 470, 1540, 620), 'fisher': (1340, 730, 1580, 930), 'cat': (1160, 630, 1420, 790)}
def side(a, b):
    c = Image.new('RGB', (a.width + b.width + 4, a.height), (255, 0, 255)); c.paste(a, (0, 0)); c.paste(b, (a.width + 4, 0)); return c
d = os.path.join(S, sys.argv[1]); surf = sys.argv[2] if len(sys.argv) > 2 else None
PREV = sys.argv[3] if len(sys.argv) > 3 else '00_base'      # 並排比較的對象（預設基準；第二階段用「前一步」）
full = Image.open(os.path.join(d, 'full_1.png')).convert('RGB')
base = Image.open(os.path.join(S, PREV, 'full_1.png')).convert('RGB')
for k, r in RECT.items(): full.crop(r).save(os.path.join(d, f'crop_{k}.png'))
if surf == 'all':
    side(base, full).save(os.path.join(d, 'compare_r3_final2.png' if 'final2' in d else 'compare_base_final.png'))
    for k, r in RECT.items(): side(base.crop(r), full.crop(r)).save(os.path.join(d, f'compare_{k}.png'))
elif surf:
    r = RECT[surf]
    full.crop(r).save(os.path.join(d, 'crop.png'))
    side(base.crop(r), full.crop(r)).save(os.path.join(d, 'compare.png'))
print('crops ->', d)
