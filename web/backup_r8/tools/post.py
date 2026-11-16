# codex 原圖 → 真正的低解析像素圖（public/tex/）。用法：python3 -I tools/post.py
# tile：縮到 N×N（環繞）＋調色盤量化；sprite：裁透明邊、縮到指定高度（px）、alpha 二值化＋調色盤量化
import os, sys, json
import numpy as np
from PIL import Image
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
RAW = os.path.join(ROOT, 'codex_work/raw'); OUT = os.path.join(ROOT, 'public/tex')
os.makedirs(OUT, exist_ok=True)
TILES = {'cobble': 64, 'plaster': 64, 'brick': 64, 'stone': 64, 'rooftile': 64, 'slate': 64, 'planks': 64}
# sprite 目標高度（低解析像素）
SPR = {'win_a': 40, 'win_b': 30, 'win_c': 40, 'win_d': 20, 'win_e': 40, 'door_a': 48, 'door_b': 50, 'hero': 44,
       'baker': 44, 'fisher': 42, 'door_open': 50, 'clump': 48, 'sign': 30, 'boat': 26, 'props': 30, 'cat': 12, 'bench': 20}

def snap(rgb, pal):
    d = ((rgb[:, :, None, :].astype(np.int32) - pal[None, None].astype(np.int32)) ** 2).sum(-1)
    return pal[d.argmin(-1)]

def palette(im_rgb, n):
    q = im_rgb.quantize(n, method=Image.MEDIANCUT, dither=Image.NONE)
    p = np.array(q.getpalette()[: n * 3], dtype=np.uint8).reshape(-1, 3)
    used = sorted(set(np.array(q).ravel().tolist()))
    return p[used]

def down_rgb(src, size):
    """先縮到 4 倍目標（box），再每 4×4 取『最接近平均的實際顏色』，保留硬邊"""
    w, h = size
    big = np.array(src.resize((w * 4, h * 4), Image.BOX), dtype=np.float32)
    b = big.reshape(h, 4, w, 4, -1).transpose(0, 2, 1, 3, 4).reshape(h, w, 16, -1)
    mean = b.mean(2, keepdims=True)
    idx = ((b - mean) ** 2).sum(-1).argmin(-1)
    return np.take_along_axis(b, idx[..., None, None], 2)[:, :, 0]

meta = {}
for name, n in TILES.items():
    p = os.path.join(RAW, name + '.png')
    if not os.path.exists(p): continue
    im = Image.open(p).convert('RGB')
    pal = palette(im, 20)
    a = snap(down_rgb(im, (n, n))[..., :3], pal)
    Image.fromarray(a.astype(np.uint8)).save(os.path.join(OUT, name + '.png'))
    meta[name] = [n, n]
for name, hpx in SPR.items():
    p = os.path.join(RAW, name + '.png')
    if not os.path.exists(p): continue
    im = Image.open(p).convert('RGBA')
    al = np.array(im)[..., 3]
    if al.min() > 200: print('!! no alpha', name); continue
    ys, xs = np.where(al > 128)
    im = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    w = max(1, round(im.width * hpx / im.height))
    pal = palette(im.convert('RGB'), 28)
    # premultiply 避免透明區的顏色滲入
    arr = np.array(im, dtype=np.float32); arr[..., :3] *= arr[..., 3:4] / 255.0
    d = down_rgb(Image.fromarray(arr.astype(np.uint8), 'RGBA'), (w, hpx))
    # alpha 用整格平均
    big = np.array(Image.fromarray(arr.astype(np.uint8), 'RGBA').resize((w, hpx), Image.BOX), dtype=np.float32)
    A = big[..., 3]
    rgb = d[..., :3] / np.maximum(d[..., 3:4] / 255.0, 0.05)
    rgb = snap(np.clip(rgb, 0, 255), pal)
    out = np.dstack([rgb, np.where(A > 110, 255, 0)]).astype(np.uint8)
    out[out[..., 3] == 0, :3] = 0
    if name == 'fisher': out = out[:, ::-1].copy()  # 面向左，釣竿伸到碼頭左側的水面上
    if name == 'baker':  # 裙子從橘黃改成藍綠，和橘色櫥窗分開
        import colorsys
        for yy in range(int(hpx * 0.5), hpx):
            for xx in range(w):
                r_, g_, b_, a_ = out[yy, xx]
                if not a_: continue
                hh, ss, vv = colorsys.rgb_to_hsv(r_ / 255, g_ / 255, b_ / 255)
                if 0.04 < hh < 0.16 and ss > 0.45 and vv > 0.35:
                    out[yy, xx, :3] = [int(c * 255) for c in colorsys.hsv_to_rgb(0.52, 0.62, vv * 0.62)]
    if name == 'baker':  # 上半身：頭髮改深棕、上衣改淺藍，從暖色櫥窗前跳出來（白頭巾、皮膚、麵包籃不動）
        import colorsys
        for yy in range(0, int(hpx * 0.5)):
            for xx in range(w):
                r_, g_, b_, a_ = out[yy, xx]
                if not a_: continue
                hh, ss, vv = colorsys.rgb_to_hsv(r_ / 255, g_ / 255, b_ / 255)
                if yy < hpx * 0.34:
                    if hh < 0.11 and ss > 0.55 and vv < 0.66: out[yy, xx, :3] = [int(c * min(1.0, vv * 1.25)) for c in (0x6a, 0x3a, 0x28)]
                elif 0.04 < hh < 0.16 and ss > 0.45 and vv > 0.55:
                    out[yy, xx, :3] = [int(c * 255) for c in colorsys.hsv_to_rgb(0.57, 0.28, min(1.0, vv * 1.1))]
    if name == 'hero':  # 補 1 px 深色外框，輪廓才清楚
        pad = np.zeros((hpx + 2, w + 2, 4), np.uint8); pad[1:-1, 1:-1] = out
        al = pad[..., 3] > 0; nb = np.zeros_like(al)
        nb[1:] |= al[:-1]; nb[:-1] |= al[1:]; nb[:, 1:] |= al[:, :-1]; nb[:, :-1] |= al[:, 1:]
        ring = nb & ~al; pad[ring] = (42, 26, 34, 255); out = pad; w += 2; hpx += 2
    Image.fromarray(out, 'RGBA').save(os.path.join(OUT, name + '.png'))
    meta[name] = [w, hpx]
json.dump(meta, open(os.path.join(OUT, 'meta.json'), 'w'))
print(meta)
# 預覽
names = list(meta)
cell = 64 * 5; W = 6
sheet = Image.new('RGB', (W * cell, ((len(names) + W - 1) // W) * cell), (90, 60, 120))
for i, n in enumerate(names):
    im = Image.open(os.path.join(OUT, n + '.png')).convert('RGBA')
    im = im.resize((im.width * 5, im.height * 5), Image.NEAREST)
    sheet.paste(im, ((i % W) * cell, (i // W) * cell), im)
sheet.save(os.path.join(ROOT, 'codex_work/preview.png'))
