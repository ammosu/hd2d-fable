# 第七輪素材後處理：python3 -I tools/post7.py   （在 post.py 之後跑；會把新項目併進 public/tex/meta.json）
import os, json, math
import numpy as np
from PIL import Image
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
RAW = os.path.join(ROOT, 'codex_work/raw'); OUT = os.path.join(ROOT, 'public/tex')
meta = json.load(open(os.path.join(OUT, 'meta.json')))

def palette(im_rgb, n):
    q = im_rgb.quantize(n, method=Image.MEDIANCUT, dither=Image.NONE)
    p = np.array(q.getpalette()[: n * 3], dtype=np.uint8).reshape(-1, 3)
    return p[sorted(set(np.array(q).ravel().tolist()))]
def snap(rgb, pal):
    d = ((rgb[:, :, None, :].astype(np.int32) - pal[None, None].astype(np.int32)) ** 2).sum(-1)
    return pal[d.argmin(-1)]
def down(src, size):
    """縮到 4 倍目標（box），每 4×4 取最接近平均的實際顏色，保留硬邊"""
    w, h = size
    big = np.array(src.resize((w * 4, h * 4), Image.BOX), dtype=np.float32)
    b = big.reshape(h, 4, w, 4, -1).transpose(0, 2, 1, 3, 4).reshape(h, w, 16, -1)
    idx = ((b - b.mean(2, keepdims=True)) ** 2).sum(-1).argmin(-1)
    return np.take_along_axis(b, idx[..., None, None], 2)[:, :, 0]
def exists(n): return os.path.exists(os.path.join(RAW, n + '.png'))
def raw(n): return Image.open(os.path.join(RAW, n + '.png'))
rs = np.random.RandomState(7)

def strips(names, band_h, out_w, out_h, n_bands, total_w):
    """把幾張平鋪圖切成橫帶、接成一長條（接縫用抖色交錯），得到不重複的長貼圖"""
    bands = []
    for n in names:
        im = raw(n).convert('RGB')
        for y in range(0, im.height - band_h + 1, band_h):
            bands.append(down(im.crop((0, y, im.width, y + band_h)), (out_w, out_h))[..., :3])
    per = len(bands) // len(names)
    inter = [bands[k * per + r] for r in range(per) for k in range(len(names))]      # 不同來源交錯
    seq = [inter[i] if i < len(inter) else inter[(i * 3 + 1) % len(inter)][:, ::-1] for i in range(n_bands)]
    gm = np.mean([b.mean((0, 1)) for b in seq], 0)
    seq = [np.clip(b * (gm / np.maximum(b.mean((0, 1)), 1)), 0, 255) for b in seq]     # 各段色調對齊
    out = np.concatenate(seq, 1)[:, :total_w]
    X = 5
    for k in range(1, len(seq)):
        x0 = k * out_w
        if x0 >= total_w: break
        for dx in range(-X, X):
            if not (0 <= x0 + dx < total_w): continue
            p = (dx + X) / (2 * X)
            src = np.concatenate(seq, 1)
            for y in range(out_h):
                if rs.rand() < (p if dx < 0 else 1 - p) * 0.5:
                    out[y, x0 + dx] = src[y, min(src.shape[1] - 1, max(0, x0 + (-dx - 1 if dx < 0 else -dx)))]
    return out

# ---------- 街面：768×44 的專屬長條（1 texel = 1 低解析像素；縱向已是螢幕列），alpha = 積水 ----------
if exists('street_a') and exists('street_b'):
    W, H = 768, 44
    a = strips(['street_a', 'street_b'], 528, 128, H, 6, W)
    pal = palette(Image.fromarray(a.astype(np.uint8)), 40)
    a = snap(a, pal).astype(np.float32)
    # 世界座標 → 貼圖座標（要和 world.js 的 streetMat 一致）
    PPM, X0, FPX, CAMY, CAMZ, ROW0 = 670 / 30, -W / 2 / (670 / 30), 670, 9, 30, 186.7
    tx = lambda x: (x - X0) * PPM
    ty = lambda z: FPX * CAMY / (CAMZ - z) - ROW0
    alpha = np.zeros((H, W), np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    for (x, z, rx, rz) in [(-0.9, 1.9, 1.5, 0.7), (4.4, 1.2, 1.3, 0.55), (10.2, 1.7, 1.7, 0.6), (-8.6, 1.3, 1.2, 0.5), (-13.5, 2.0, 1.4, 0.5), (7.2, -0.6, 0.9, 0.4)]:
        cx, cy = tx(x), ty(z); ax, ay = rx * PPM, max(2.0, ty(z + rz) - ty(z))
        d = ((xx - cx) / ax) ** 2 + ((yy - cy) / ay) ** 2
        wob = np.sin(xx * 0.55 + cy) * 0.18 + np.sin(yy * 1.3 + cx * 0.3) * 0.12
        alpha = np.maximum(alpha, (d + wob < 1.0).astype(np.float32))
    # 遠側（牆腳、人行道邊）與堤邊略暗，中間磨亮一點
    v = np.linspace(0, 1, H)[:, None]
    a *= (0.86 + 0.22 * np.sin(v * math.pi))[..., None]
    out = np.dstack([np.clip(a, 0, 255), alpha * 255]).astype(np.uint8)
    Image.fromarray(out, 'RGBA').save(os.path.join(OUT, 'street7.png')); meta['street7'] = [W, H]

# ---------- 堤岸：768×22 長條，加水線污痕與苔 ----------
if exists('quay'):
    W, H = 768, 22
    a = strips(['quay'], 250, 128, H, 6, W).astype(np.float32)
    v = np.linspace(0, 1, H)[:, None, None]            # 0 上緣 → 1 水線
    n = rs.rand(1, W, 1); n = np.repeat(n, H, 0)
    stain = np.clip((v - 0.55 - 0.25 * np.sin(np.arange(W)[None, :, None] * 0.07) * 0.3) / 0.45, 0, 1)
    a *= 1 - 0.45 * stain                              # 水線以上的濕痕
    green = np.clip((v - 0.72) / 0.28, 0, 1) * (n > 0.35)
    a = a * (1 - 0.5 * green) + np.array([52, 74, 40], np.float32) * 0.5 * green
    pal = palette(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), 32)
    Image.fromarray(snap(np.clip(a, 0, 255), pal).astype(np.uint8)).save(os.path.join(OUT, 'quay7.png')); meta['quay7'] = [W, H]

# ---------- 屋頂：128×128（深淺、缺瓦、苔都在圖裡） ----------
for n in ['roof_red2', 'roof_slate2']:
    if not exists(n): continue
    im = raw(n).convert('RGB'); s = min(im.size); im = im.crop((0, 0, s, s))
    a = down(im, (128, 128))[..., :3]
    Image.fromarray(snap(a, palette(im, 28)).astype(np.uint8)).save(os.path.join(OUT, n + '.png')); meta[n] = [128, 128]

# ---------- 天空：縮到「一個藝術像素 = 1 texel」 ----------
if exists('sky'):
    im = raw('sky').convert('RGB')
    a = down(im, (418, 235))[..., :3]
    Image.fromarray(snap(a, palette(im, 48)).astype(np.uint8)).save(os.path.join(OUT, 'sky7.png')); meta['sky7'] = [418, 235]

# ---------- 一列多個元件：切開 ----------
def split_row(n, tallest_px, top_align=False):
    im = raw(n).convert('RGBA'); al = np.array(im)[..., 3] > 128
    cols = al.any(0); parts = []; start = None; gap = 0
    for x in range(im.width + 1):
        on = x < im.width and cols[x]
        if on:
            if start is None: start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap > 14 or x == im.width: parts.append((start, x - gap + 1)); start = None
    parts = [p for p in parts if p[1] - p[0] > 20]
    boxes = []
    for (x0, x1) in parts:
        ys = np.where(al[:, x0:x1].any(1))[0]; boxes.append((x0, ys.min(), x1, ys.max() + 1))
    k = tallest_px / max(b[3] - b[1] for b in boxes)
    pal = palette(im.convert('RGB'), 40)
    res = []
    for (x0, y0, x1, y1) in boxes:
        c = im.crop((x0, y0, x1, y1)); w, h = max(2, round(c.width * k)), max(2, round(c.height * k))
        arr = np.array(c, dtype=np.float32); arr[..., :3] *= arr[..., 3:4] / 255.0
        pm = Image.fromarray(arr.astype(np.uint8), 'RGBA')
        d = down(pm, (w, h)); A = np.array(pm.resize((w, h), Image.BOX), dtype=np.float32)[..., 3]
        rgb = snap(np.clip(d[..., :3] / np.maximum(d[..., 3:4] / 255.0, 0.05), 0, 255), pal)
        o = np.dstack([rgb, np.where(A > 110, 255, 0)]).astype(np.uint8); o[o[..., 3] == 0, :3] = 0
        res.append(o)
    return res

def save_each(n, tallest):
    if not exists(n): return 0
    parts = split_row(n, tallest)
    for i, o in enumerate(parts):
        Image.fromarray(o, 'RGBA').save(os.path.join(OUT, f'{n}_{i}.png')); meta[f'{n}_{i}'] = [o.shape[1], o.shape[0]]
    return len(parts)
print('vines', save_each('vines', 34), 'patches', save_each('patches', 26), 'props7', save_each('props7', 30))

# 草與花：打包成一張圖集（每格 CW×CH，底部對齊、水平置中）
if exists('tufts') and exists('flowers'):
    parts = split_row('tufts', 15) + split_row('flowers', 15)
    CW = max(p.shape[1] for p in parts); CW += CW % 2; CH = max(p.shape[0] for p in parts)
    atlas = np.zeros((CH, CW * len(parts), 4), np.uint8)
    for i, o in enumerate(parts):
        x = i * CW + (CW - o.shape[1]) // 2; atlas[CH - o.shape[0]:, x:x + o.shape[1]] = o
    Image.fromarray(atlas, 'RGBA').save(os.path.join(OUT, 'plants7.png')); meta['plants7'] = [atlas.shape[1], CH]
    meta['plants7_cells'] = [len(parts), CW, CH]
    print('plants', len(parts), CW, CH)

# 單一元件
SPR = {'cart': 30, 'win_shut': 20, 'win_box': 24, 'branch': 96}
for n, hpx in SPR.items():
    if not exists(n): continue
    im = raw(n).convert('RGBA'); al = np.array(im)[..., 3]
    if al.min() > 200: print('!! no alpha', n); continue
    ys, xs = np.where(al > 128); im = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    w = max(1, round(im.width * hpx / im.height)); pal = palette(im.convert('RGB'), 28)
    arr = np.array(im, dtype=np.float32); arr[..., :3] *= arr[..., 3:4] / 255.0
    pm = Image.fromarray(arr.astype(np.uint8), 'RGBA')
    d = down(pm, (w, hpx)); A = np.array(pm.resize((w, hpx), Image.BOX), dtype=np.float32)[..., 3]
    rgb = snap(np.clip(d[..., :3] / np.maximum(d[..., 3:4] / 255.0, 0.05), 0, 255), pal)
    o = np.dstack([rgb, np.where(A > 110, 255, 0)]).astype(np.uint8); o[o[..., 3] == 0, :3] = 0
    Image.fromarray(o, 'RGBA').save(os.path.join(OUT, n + '.png')); meta[n] = [w, hpx]

# 窗的變體：換花色、換百葉窗顏色（打破重複）
import colorsys
def recolor(src, dst, fn):
    im = np.array(Image.open(os.path.join(OUT, src + '.png')).convert('RGBA'))
    for y in range(im.shape[0]):
        for x in range(im.shape[1]):
            r, g, b, a = im[y, x]
            if not a: continue
            h, sa, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            n = fn(h, sa, v)
            if n: im[y, x, :3] = [int(c * 255) for c in colorsys.hsv_to_rgb(*n)]
    Image.fromarray(im, 'RGBA').save(os.path.join(OUT, dst + '.png')); meta[dst] = meta[src]
red = lambda h, s, v: (h < 0.035 or h > 0.95) and s > 0.55
recolor('win_a', 'win_a2', lambda h, s, v: (0.78, s * 0.7, min(1, v * 1.05)) if red(h, s, v) else None)   # 紫花
recolor('win_a', 'win_a3', lambda h, s, v: (0.10, 0.12, min(1, v * 1.25)) if red(h, s, v) else None)      # 白花
recolor('win_b', 'win_b2', lambda h, s, v: (0.03, s * 0.75, v * 0.8) if 0.40 < h < 0.56 and s > 0.25 else None)  # 紅褐百葉窗
json.dump(meta, open(os.path.join(OUT, 'meta.json'), 'w'))
# 預覽
names = [k for k in meta if k.endswith('7') or '7_' in k and not k.endswith('cells') or k in SPR or k.startswith('roof_')]
names = [k for k in names if os.path.exists(os.path.join(OUT, k + '.png'))]
sheet = Image.new('RGB', (1900, 1000), (90, 60, 120)); x = y = 6; rowh = 0
for n in names:
    im = Image.open(os.path.join(OUT, n + '.png')).convert('RGBA'); sc = 2 if im.width > 300 else 4
    im = im.resize((im.width * sc, im.height * sc), Image.NEAREST)
    if x + im.width > 1890: x = 6; y += rowh + 8; rowh = 0
    sheet.paste(im, (x, y), im); x += im.width + 10; rowh = max(rowh, im.height)
sheet.save(os.path.join(ROOT, 'codex_work/preview7.png'))
