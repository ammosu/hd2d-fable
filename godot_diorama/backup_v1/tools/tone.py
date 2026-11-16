#!/usr/bin/env python3
"""三階明度對照：把每張圖縮到 32×18、分成暗／中／亮三階，並排輸出。
python3 tools/tone.py out.png 標籤=路徑 標籤=路徑 ...   （門檻：亮度 <70 暗、70–150 中、>150 亮）"""
import sys
import numpy as np
from PIL import Image, ImageDraw
out = sys.argv[1]; items = [a.split('=', 1) for a in sys.argv[2:]]
S = 14; W, H = 32 * S, 18 * S
sheet = Image.new('RGB', (len(items) * (W + 10), H * 2 + 40), (40, 40, 48)); d = ImageDraw.Draw(sheet)
for k, (lab, path) in enumerate(items):
    im = Image.open(path).convert('RGB')
    small = im.resize((32, 18), Image.BOX)
    l = np.array(small.convert('L')).astype(float)
    t = np.where(l < 70, 20, np.where(l < 150, 120, 235)).astype(np.uint8)
    x = k * (W + 10)
    sheet.paste(small.resize((W, H), Image.NEAREST), (x, 20))
    sheet.paste(Image.fromarray(t, 'L').convert('RGB').resize((W, H), Image.NEAREST), (x, H + 30))
    d.text((x + 4, 4), f"{lab}  dark {(l<70).mean()*100:.0f}% mid {((l>=70)&(l<150)).mean()*100:.0f}% light {(l>=150).mean()*100:.0f}%", fill=(255, 255, 255))
    print(f"{lab}: 暗 {(l<70).mean()*100:.0f}%  中 {((l>=70)&(l<150)).mean()*100:.0f}%  亮 {(l>=150).mean()*100:.0f}%")
sheet.save(out)
