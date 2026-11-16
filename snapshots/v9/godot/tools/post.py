#!/usr/bin/env python3
"""codex 生圖後處理：tools/raw/<name>.png（放大的假像素）→ tex/<name>.png（真實點陣解析度）
  1. 偵測點陣格距（x、y 各自），每格取中央區域的中位數顏色 → 還原成 1 點陣 = 1 像素
  2. sprite：alpha 二值化；整張若有多個元件就依連通區塊切開（<name>_0.png, _1.png …，由左到右、上到下）
  3. 量化成有限色數，四周留 PAD 像素透明邊（給逐列搖擺位移用）
  4. tex/meta.json 記錄每張的像素尺寸
用法： python3 tools/post.py [name ...]"""
import json, os, sys
import numpy as np
from PIL import Image

T = os.path.dirname(os.path.abspath(__file__))
RAW, OUT = os.path.join(T, 'raw'), os.path.join(T, '..', 'tex')
A = json.load(open(os.path.join(T, 'assets.json')))
PAD = 4
META_PATH = os.path.join(OUT, 'meta.json')
meta = json.load(open(META_PATH)) if os.path.exists(META_PATH) else {}


def autoc(g, maxlag=64):
    g = g - g.mean()
    return np.array([(g[:-l] * g[l:]).mean() if l else (g * g).mean() for l in range(maxlag)])


def find_pitch(gx, gy):
    """兩軸共用同一格距（點陣是正方形）：自相關的第一個強峰，再用高倍數峰修正成小數"""
    ac = autoc(gx) / (gx.var() + 1e-9) + autoc(gy) / (gy.var() + 1e-9)
    mx = ac[6:48].max()
    p = None
    for l in range(6, 48):
        if ac[l] >= 0.6 * mx and ac[l] >= ac[l - 1] and ac[l] >= ac[l + 1]:
            p = l; break
    # 用長距離的自相關修正
    best = float(p)
    for k in (2, 3):
        c = int(round(best * k))
        if c + 2 < len(ac):
            w = ac[c - 1:c + 2]
            j = c - 1 + int(np.argmax(w))
            d = 0.0
            if 0 < j < len(ac) - 1:
                den = ac[j - 1] - 2 * ac[j] + ac[j + 1]
                if den < 0: d = 0.5 * (ac[j - 1] - ac[j + 1]) / den
            best = (j + d) / k
    return best


def edges(g, p):
    """沿著軸追蹤每一條格線：從最清楚的位置出發，每走一格在 ±tol 內吸附到最強的邊"""
    n = len(g)
    gs = np.convolve(g, [0.25, 0.5, 0.25], mode='same')
    # 起點相位：梳狀取樣分數最高者（只用中央一段，避免漂移）
    lo, hi = int(n * 0.3), int(n * 0.7)
    bs, bph = -1, 0
    for ph in np.arange(0, p, 0.5):
        idx = np.round(lo + ph + np.arange(int((hi - lo) / p)) * p).astype(int)
        s = gs[idx].mean()
        if s > bs: bs, bph = s, ph
    start = lo + bph
    tol = max(1, int(p * 0.18)); thr = gs.mean() * 1.2
    def walk(pos, step):
        out = []
        while True:
            pos += step
            if pos < 0 or pos > n - 1: break
            c = int(round(pos)); a0, a1 = max(0, c - tol), min(n, c + tol + 1)
            j = a0 + int(np.argmax(gs[a0:a1]))
            if gs[j] > thr: pos = pos * 0.5 + j * 0.5
            out.append(pos)
        return out
    e = sorted(walk(start + p, -p) + walk(start, p))
    return [int(round(x)) + 1 for x in e]


def depixel(im, is_tile, force_p=None):
    a = np.array(im.convert('RGBA')).astype(np.float32)
    w = (a[..., 3:4] / 255.0)
    rgbw = a[..., :3] * (1 if is_tile else w)
    full = np.concatenate([rgbw, a[..., 3:4]], axis=2)
    gx = np.abs(np.diff(full, axis=1)).sum(axis=(0, 2))
    gy = np.abs(np.diff(full, axis=0)).sum(axis=(1, 2))
    p = force_p or find_pitch(gx, gy)
    H, W = a.shape[:2]
    ex = [0] + [e for e in edges(gx, p) if 0 < e < W] + [W]
    ey = [0] + [e for e in edges(gy, p) if 0 < e < H] + [H]
    def cells(e):
        c = [(e[i], e[i + 1]) for i in range(len(e) - 1)]
        return [x for x in c if x[1] - x[0] >= p * 0.5]
    cx, cy = cells(ex), cells(ey)
    out = np.zeros((len(cy), len(cx), 4), np.uint8)
    for j, (y0, y1) in enumerate(cy):
        m = max(1, int((y1 - y0) * 0.25))
        for i, (x0, x1) in enumerate(cx):
            n = max(1, int((x1 - x0) * 0.25))
            blk = a[y0 + m:y1 - m, x0 + n:x1 - n].reshape(-1, 4)
            if len(blk) == 0: blk = a[y0:y1, x0:x1].reshape(-1, 4)
            al = np.median(blk[:, 3])
            if is_tile or al > 127:
                sel = blk if is_tile else blk[blk[:, 3] > 127]
                out[j, i, :3] = np.median(sel[:, :3], axis=0)
                out[j, i, 3] = 255
    return out, p, p


def quant(rgba, colors):
    im = Image.fromarray(rgba[..., :3], 'RGB').quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert('RGB')
    o = rgba.copy(); o[..., :3] = np.array(im)
    o[o[..., 3] == 0] = 0
    return o


def label(mask):
    """4 連通區塊標記（小圖，直接 BFS）"""
    H, W = mask.shape
    lab = np.zeros((H, W), np.int32); n = 0
    for y in range(H):
        for x in range(W):
            if mask[y, x] and not lab[y, x]:
                n += 1; st = [(y, x)]; lab[y, x] = n
                while st:
                    cy, cx = st.pop()
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = n; st.append((ny, nx))
    return lab, n


def dilate(m, r):
    o = m.copy()
    for _ in range(r):
        p = np.pad(o, 1)
        o = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return o


def save_sprite(name, rgba):
    al = rgba[..., 3] > 0
    ys, xs = np.where(al)
    c = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    c = np.pad(c, ((PAD, PAD), (PAD, PAD), (0, 0)))
    Image.fromarray(c, 'RGBA').save(os.path.join(OUT, name + '.png'))
    meta[name] = [c.shape[1], c.shape[0]]
    return c.shape[1] - 2 * PAD, c.shape[0] - 2 * PAD


def main():
    names = sys.argv[1:] or [n for n in A if os.path.exists(os.path.join(RAW, n + '.png'))]
    for name in names:
        a = A[name]; tile = a['kind'] in ('tile', 'image')
        src = Image.open(os.path.join(RAW, name + '.png'))
        if max(src.size) <= 256:   # codex 有時直接給真實解析度
            out, px, py = np.array(src.convert('RGBA')), 1, 1
        else:
            fp = a.get('pitch') or (src.width / a['cells_w'] if a.get('cells_w') else None)   # 自動偵測失敗時可在 assets.json 指定格距或橫向點陣數
            out, px, py = depixel(src, tile, fp)
        if tile:
            if a.get('neutral'):   # 去飽和並拉到固定平均亮度（之後由引擎乘上顏色）
                f = out[..., :3].astype(np.float32); g = f.mean(axis=2, keepdims=True)
                f = g + (f - g) * a.get('sat', 0.3); f *= a.get('mean', 160) / max(f.mean(), 1)
                out[..., :3] = np.clip(f, 0, 255).astype(np.uint8)
            out = quant(out, a.get('colors', 20))
            Image.fromarray(out[..., :3], 'RGB').save(os.path.join(OUT, name + '.png'))
            meta[name] = [out.shape[1], out.shape[0]]
            print(f'{name}: tile pitch {px:.2f}/{py:.2f} → {out.shape[1]}x{out.shape[0]}')
            continue
        out = quant(out, a.get('colors', 32))
        # 去掉孤立的雜點
        lab, n = label(out[..., 3] > 0)
        for i in range(1, n + 1):
            if (lab == i).sum() < 3: out[lab == i] = 0
        m = dilate(out[..., 3] > 0, a.get('gap', 2))
        lab, n = label(m)
        boxes = []
        for i in range(1, n + 1):
            ys, xs = np.where((lab == i) & (out[..., 3] > 0))
            if len(ys) < a.get('min_area', 40): continue
            boxes.append((ys.min(), xs.min(), ys.max(), xs.max(), i))
        if len(boxes) <= 1 or a.get('single'):
            w, h = save_sprite(name, out)
            print(f'{name}: sprite pitch {px:.2f}/{py:.2f} → {w}x{h}')
        else:
            # 排序：先分列（y 中心相近的算同一列），再由左到右
            boxes.sort(key=lambda b: (b[0] + b[2]) / 2)
            rows = []; cur = [boxes[0]]
            for b in boxes[1:]:
                if (b[0] + b[2]) / 2 < cur[-1][2]: cur.append(b)
                else: rows.append(cur); cur = [b]
            rows.append(cur)
            k = 0; sizes = []
            for r in rows:
                for b in sorted(r, key=lambda b: b[1]):
                    part = out.copy(); part[lab != b[4]] = 0
                    sizes.append(save_sprite(f'{name}_{k}', part)); k += 1
            for old in range(k, 12):
                meta.pop(f'{name}_{old}', None)
            meta[name + '_n'] = k
            print(f'{name}: sheet pitch {px:.2f}/{py:.2f} → {k} parts {sizes}')
    json.dump(meta, open(META_PATH, 'w'), indent=1)


main()
