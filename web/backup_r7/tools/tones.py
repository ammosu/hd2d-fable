# 三階明度對照：python3 -I tools/tones.py out.png 標籤=圖 ...   每張縮到 32×18、分成暗／中／亮三階
import sys, numpy as np
from PIL import Image, ImageDraw
out, items = sys.argv[1], [a.split('=', 1) for a in sys.argv[2:]]
S = 12; W, H = 32 * S, 18 * S
sheet = Image.new('RGB', (len(items) * (W + 8) + 8, H * 2 + 44), (40, 40, 40)); d = ImageDraw.Draw(sheet)
for i, (lab, f) in enumerate(items):
    im = Image.open(f).convert('RGB')
    sm = im.resize((32, 18), Image.BOX)
    l = np.array(sm.convert('L'), dtype=np.float32)
    t = np.where(l < 60, 20, np.where(l < 130, 120, 245)).astype(np.uint8)
    x = 8 + i * (W + 8)
    sheet.paste(sm.resize((W, H), Image.NEAREST), (x, 20))
    sheet.paste(Image.fromarray(t).convert('RGB').resize((W, H), Image.NEAREST), (x, 28 + H))
    frac = [(l < 60).mean(), ((l >= 60) & (l < 130)).mean(), (l >= 130).mean()]
    d.text((x, 4), f'{lab}  dark {frac[0]*100:.0f}%  mid {frac[1]*100:.0f}%  light {frac[2]*100:.0f}%', fill=(255, 255, 120))
    print(lab, ' '.join(f'{v*100:.0f}%' for v in frac))
sheet.save(out)
