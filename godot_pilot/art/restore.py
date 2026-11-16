#!/usr/bin/env python3
"""pilot：把 codex 的放大假像素還原成 1 點陣 = 1 像素，並量化到共用調色盤。
depixel / find_pitch / edges 取自 tools/post.py（原檔 import 時會直接執行 main，所以複製過來），find_pitch 的搜尋範圍改成可指定。
  restore(raw_path, pitch=None, grid=True) → RGBA uint8 陣列（真點陣）
     grid=True ：圖本身是對齊格線的假像素 → 追蹤格線、每格取中央的中位數顏色
     grid=False：圖是平滑的插畫（codex 在小格距下不會畫成格子）→ 以固定格距取每格中央區域的中位數（等於重新點陣化）
  to_palette(rgba, colors, ...) → 量化到調色盤子集合（最近色，不抖色）
  check(raw, out, pitch) → 把結果放大回去與原圖比較的平均誤差（確認還原沒有走樣）"""
import os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from palette import PAL, sub

def autoc(g, maxlag=80):
    g = g - g.mean()
    return np.array([(g[:-l] * g[l:]).mean() if l else (g * g).mean() for l in range(maxlag)])


def find_pitch(gx, gy, lo=6, hi=48):
    """兩軸共用同一格距（點陣是正方形）：自相關的第一個強峰，再用高倍數峰修正成小數"""
    ac = autoc(gx) / (gx.var() + 1e-9) + autoc(gy) / (gy.var() + 1e-9)
    mx = ac[lo:hi].max()
    p = None
    for l in range(lo, hi):
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



def restore(path, pitch=None, grid=True, lo=6, hi=48, lines=0.0):
    im = Image.open(path).convert('RGBA')
    if grid:
        a = np.array(im).astype(np.float32)
        if pitch is None:
            w = a[..., 3:4] / 255.0
            full = np.concatenate([a[..., :3] * w, a[..., 3:4]], axis=2)
            gx = np.abs(np.diff(full, axis=1)).sum(axis=(0, 2)); gy = np.abs(np.diff(full, axis=0)).sum(axis=(1, 2))
            pitch = find_pitch(gx, gy, lo, hi)
        out, p, _ = depixel(im, im.getextrema()[3][0] == 255, force_p=pitch)
        return out, p
    a = np.array(im).astype(np.float32); H, W = a.shape[:2]
    nx, ny = int(W / pitch), int(H / pitch)
    out = np.zeros((ny, nx, 4), np.uint8)
    for j in range(ny):
        y0, y1 = int(j * pitch), int((j + 1) * pitch); m = max(1, int((y1 - y0) * 0.3))
        for i in range(nx):
            x0, x1 = int(i * pitch), int((i + 1) * pitch); n = max(1, int((x1 - x0) * 0.3))
            blk = a[y0 + m:y1 - m, x0 + n:x1 - n].reshape(-1, 4)
            med = np.median(blk, axis=0)
            if lines > 0:      # 保留比一格還細的深色線（瓦縫、石縫）：整格裡深色像素超過一定比例就取深色
                cell = a[y0:y1, x0:x1].reshape(-1, 4); lum = cell[:, :3].sum(1)
                dark = lum < med[:3].sum() * 0.72
                if dark.mean() >= lines and dark.mean() < 0.5: med = np.median(cell[dark], axis=0)
            out[j, i] = med
    out[..., 3] = 255
    return out, pitch

def to_palette(rgba, colors, mask=None):
    """最近色量化（redmean 加權距離），不抖色。colors：RGB tuple 清單；mask：只量化這些像素"""
    pal = np.array(colors, np.float32)
    px = rgba[..., :3].astype(np.float32)
    rm = (px[..., None, 0] + pal[None, None, :, 0]) / 2
    d = px[..., None, :] - pal[None, None, :, :]
    dist = (2 + rm / 256) * d[..., 0] ** 2 + 4 * d[..., 1] ** 2 + (2 + (255 - rm) / 256) * d[..., 2] ** 2
    idx = dist.argmin(-1)
    out = rgba.copy(); q = pal[idx].astype(np.uint8)
    if mask is None: mask = np.ones(rgba.shape[:2], bool)
    out[..., :3][mask] = q[mask]
    out[out[..., 3] == 0] = 0
    return out

def despeckle(img, keep, min_px=5, rounds=2):
    """量化後清掉「抖色亂點」：同色連通區塊小於 min_px 的，併入周圍最多的顏色。keep(color)->True 的顏色（苔、落葉、石縫）不動。
    這是還原階段的一部分（codex 的平滑漸層被量化後會碎成亂點），不算手修。回傳 (結果, 改掉的像素數)"""
    a = img.copy(); H, W = a.shape[:2]; changed = 0
    for _ in range(rounds):
        key = a[..., 0].astype(np.int32) << 16 | a[..., 1].astype(np.int32) << 8 | a[..., 2]
        seen = np.zeros((H, W), bool)
        for y in range(H):
            for x in range(W):
                if seen[y, x]: continue
                k = key[y, x]; st = [(y, x)]; seen[y, x] = True; comp = []; nb = {}
                while st:
                    cy, cx = st.pop(); comp.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        yy, xx = cy + dy, cx + dx
                        if 0 <= yy < H and 0 <= xx < W:
                            if key[yy, xx] == k:
                                if not seen[yy, xx]: seen[yy, xx] = True; st.append((yy, xx))
                            else: nb[key[yy, xx]] = nb.get(key[yy, xx], 0) + 1
                    if len(comp) > min_px: break
                if len(comp) <= min_px and not st and nb:
                    col = (k >> 16 & 255, k >> 8 & 255, k & 255)
                    if keep(col): continue
                    cand = sorted(nb.items(), key=lambda t: -t[1])
                    cand = [c for c in cand if not keep((c[0] >> 16 & 255, c[0] >> 8 & 255, c[0] & 255))] or cand
                    nk = cand[0][0]
                    for cy, cx in comp: a[cy, cx, :3] = (nk >> 16 & 255, nk >> 8 & 255, nk & 255); changed += 1
    return a, changed

def tone(rgba, gain=1.0, sat=1.0, shift=(0, 0, 0), gamma=1.0):
    f = rgba[..., :3].astype(np.float32) / 255
    f = f ** gamma
    g = f.mean(axis=2, keepdims=True); f = g + (f - g) * sat
    f = f * gain + np.array(shift, np.float32) / 255
    o = rgba.copy(); o[..., :3] = np.clip(f * 255, 0, 255).astype(np.uint8); return o

def check(path, out, pitch):
    raw = np.array(Image.open(path).convert('RGBA')).astype(np.float32)
    up = np.array(Image.fromarray(out).resize((raw.shape[1], raw.shape[0]), Image.NEAREST)).astype(np.float32)
    return float(np.abs(raw[..., :3] - up[..., :3])[raw[..., 3] > 127].mean())

def up(a, k=8):
    im = Image.fromarray(a) if not isinstance(a, Image.Image) else a
    return im.resize((im.width * k, im.height * k), Image.NEAREST)

if __name__ == '__main__':
    for f in sys.argv[1:]:
        o, p = restore(f); print(f, 'pitch %.3f' % p, o.shape, 'err %.1f' % check(f, o, p))
        Image.fromarray(o).save(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'work', os.path.basename(f).replace('.png', '_rest.png')))
