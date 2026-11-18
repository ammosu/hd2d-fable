#!/usr/bin/env python3
"""遠景秋山瀑布（參考使用者照片，codex 重畫）：art/raw/bg_falls_v*.png → tex/pilot_bg_falls.png（640×~77 點陣，鏡頭前 3 px／點陣＝1920 寬）。
去背（洋紅）→ 縮成點陣（÷6）→ 限色 → 黃昏暮靄（往天空色混）→ 兩側用左右半邊鏡像補到 640 寬（瀑布只留中間一道）。"""
import os, glob, json
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); T = os.path.join(A, '..', 'tex')
f = sorted(glob.glob(os.path.join(A, 'raw', 'bg_falls_v*.png')))[-1]
a = np.asarray(Image.open(f).convert('RGB')).astype(float)
mag = (np.abs(a[..., 0] - 255) + a[..., 1] + np.abs(a[..., 2] - 255)) < 120
y0, y1, S = 444, 900, 6
c = a[y0:y1]; m = mag[y0:y1]
h, w = c.shape[0] // S, c.shape[1] // S
c = c[:h * S, :w * S].reshape(h, S, w, S, 3); m = m[:h * S, :w * S].reshape(h, S, w, S)
keep = m.mean((1, 3)) < 0.5
cs = np.where(m[..., None], np.nan, c)
col = np.nanmedian(cs.reshape(h, S, w, S, 3).transpose(0, 2, 1, 3, 4).reshape(h, w, S * S, 3), axis=2)
col = np.nan_to_num(col)
# 暮靄：越上面（越遠的稜線）越淡、越接近天空色
sky = np.array([150, 104, 150.0])
t = np.linspace(0.55, 0.3, h)[:, None, None] * np.ones((1, w, 1))
lum = col.mean(2, keepdims=True); t = np.where(lum > 175, t * 0.35, t)      # 瀑布（最亮的白）少一點暮靄，才看得出水
col = col * (1 - t) + sky * t
fall = (c.reshape(h, S, w, S, 3).mean((1, 3)).min(2) > 175) & keep
img = Image.fromarray(col.clip(0, 255).astype(np.uint8)).quantize(40, dither=Image.Dither.NONE).convert('RGB')
q = np.asarray(img).copy(); q[fall] = (228, 218, 230)      # 瀑布保持白
core = np.dstack([q, (keep * 255).astype(np.uint8)])
# 中段（含瀑布）＋兩側鏡像（避開瀑布：只取左半與右半的外側）
W = 840
half = w // 2
# 兩側不用鏡像（會出現對稱的 V 形），改接原圖不含瀑布的段落（瀑布在 x≈155–163）；挑稜線高度對得上的切點，避免斷差
def ridge(x): return int(np.argmax(x[..., 3] > 0, axis=0).mean()) if x.ndim == 3 else 0
top = np.argmax(core[..., 3] > 0, axis=0)
src = np.concatenate([core[:, 172:], core[:, :140]] * 3, axis=1); stop = np.argmax(src[..., 3] > 0, axis=0)
need = (W - w) // 2; need2 = W - w - need
best = min(range(src.shape[1] - need), key=lambda i: abs(int(stop[i + need - 1]) - int(top[0])) * 3 + abs(int(stop[i + need - 2]) - int(stop[i + need - 1])))
L = src[:, best:best + need]
best2 = min(range(src.shape[1] - need2), key=lambda i: abs(int(stop[i]) - int(top[-1])) * 3 + (0 if abs(i - best) > 60 else 100))
R = src[:, best2:best2 + need2]
out = np.concatenate([L, core, R], axis=1)
# 底部往下補 25 列（重複最下面幾列的樹林），免得山腳下露出一條平的天空色
out = np.concatenate([out, np.concatenate([out[-5:]] * 5, axis=0)], axis=0)
out[-30:, :, 3] = 255
print('size', out.shape)
Image.fromarray(out).save(os.path.join(T, 'pilot_bg_falls.png'))
mp = os.path.join(T, 'meta.json'); mt = json.load(open(mp)); mt['pilot_bg_falls'] = [out.shape[1], out.shape[0]]; json.dump(mt, open(mp, 'w'))
Image.fromarray(out).resize((out.shape[1] * 3, out.shape[0] * 3), Image.NEAREST).save('/tmp/bg_falls_x3.png')
