// 程式畫的像素貼圖（葉叢、草花、鳥、蝴蝶、樹皮、遠山…）
import * as THREE from 'three';

export function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function canvasTex(w, h, draw, { repeat = false } = {}) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(w, h);
  const set = (x, y, col) => {
    x |= 0; y |= 0;
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    const i = (y * w + x) * 4;
    img.data[i] = col[0]; img.data[i + 1] = col[1]; img.data[i + 2] = col[2]; img.data[i + 3] = col[3] ?? 255;
  };
  const get = (x, y) => { const i = ((y | 0) * w + (x | 0)) * 4; return [img.data[i], img.data[i + 1], img.data[i + 2], img.data[i + 3]]; };
  draw(set, get, w, h);
  ctx.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  pix(t, repeat);
  t.userData = { w, h };
  return t;
}
export function pix(t, repeat = false) {
  t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter; t.generateMipmaps = false;
  t.colorSpace = THREE.SRGBColorSpace;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}
const g = (v, a = 255) => [v, v, v, a];

// 2×2 葉叢圖集（每格 16×16，灰階，交給 instance color 上色）
export function leafAtlas() {
  return canvasTex(32, 32, (set) => {
    const r = rng(7);
    for (let cell = 0; cell < 4; cell++) {
      const ox = (cell % 2) * 16, oy = (cell >> 1) * 16;
      const n = 7 + (cell % 2) * 2;
      for (let i = 0; i < n; i++) {
        const a = r() * 6.28, rad = r() * 4.6;
        const cx = 8 + Math.cos(a) * rad, cy = 8 + Math.sin(a) * rad * 0.85;
        const len = 2 + (r() * 2 | 0), dir = r() < 0.5 ? 1 : -1;
        // 一片葉子：斜向小菱形，左上亮、右下暗
        for (let k = -len; k <= len; k++) {
          const wdt = len - Math.abs(k);
          for (let j = -wdt; j <= wdt; j++) {
            const x = cx + k + (dir > 0 ? j : -j) * 0.5, y = cy + j * 0.8 - k * 0.35 * dir;
            if (x < 0.5 || y < 0.5 || x > 14.5 || y > 14.5) continue;
            const tone = j < 0 ? 255 : j === 0 ? 205 : 150;
            set(ox + x, oy + y, g(tone));
          }
        }
      }
    }
  });
}

// 植物圖集：8 格（每格 8×12）：草1 草2 粉花 白花 黃花 紅花 蘆葦 藍花
export function plantAtlas() {
  return canvasTex(64, 12, (set) => {
    const r = rng(21);
    const G1 = [70, 120, 52], G2 = [104, 158, 60], G3 = [150, 196, 84];
    const blade = (ox, x, h, lean, c) => { for (let y = 0; y < h; y++) set(ox + x + Math.round(lean * y / h), 11 - y, y > h - 2 ? G3 : c); };
    for (let cell = 0; cell < 8; cell++) {
      const ox = cell * 8;
      if (cell < 2) {
        for (let i = 0; i < 6; i++) blade(ox, 1 + i + (r() * 1.2 | 0), 3 + (r() * 5 | 0), (r() - 0.5) * 3, r() < 0.5 ? G1 : G2);
      } else if (cell === 6) { // 蘆葦
        for (let i = 0; i < 3; i++) { const x = 2 + i * 2, h = 8 + (r() * 4 | 0); blade(ox, x, h, (r() - 0.5) * 2, [120, 130, 60]); set(ox + x, 12 - h, [110, 70, 40]); set(ox + x, 13 - h, [130, 84, 46]); }
      } else {
        const cols = { 2: [[250, 150, 190], [255, 205, 225]], 3: [[235, 235, 245], [255, 255, 255]], 4: [[250, 200, 60], [255, 236, 130]], 5: [[214, 60, 58], [250, 110, 90]], 7: [[110, 140, 240], [170, 196, 255]] }[cell];
        for (let i = 0; i < 3; i++) {
          const x = 1 + i * 2 + (r() * 2 | 0), h = 4 + (r() * 5 | 0);
          blade(ox, x, h, 0, G1);
          set(ox + x, 11 - h, cols[0]); set(ox + x + 1, 11 - h, cols[0]); set(ox + x, 10 - h, cols[1]); set(ox + x - 1, 11 - h, cols[1]);
        }
        blade(ox, 6, 3, 1, G2); blade(ox, 0, 2, -1, G2);
      }
    }
  });
}

// 鳥：2 影格（各 8×6），翅膀上／下
export function birdTex() {
  return canvasTex(16, 6, (set) => {
    const c = [38, 30, 52];
    // 上揚
    [[0, 0], [1, 1], [2, 2], [3, 3], [4, 3], [5, 2], [6, 1], [7, 0], [3, 2], [4, 2], [3, 4], [4, 4]].forEach(([x, y]) => set(x, y, c));
    // 下壓
    [[0, 4], [1, 3], [2, 2], [3, 2], [4, 2], [5, 2], [6, 3], [7, 4], [3, 3], [4, 3], [3, 1], [4, 1]].forEach(([x, y]) => set(8 + x, y, c));
  });
}
// 蝴蝶：2 影格（各 9×7，白，交給 instance color）：張翅／半收
export function butterflyTex() {
  return canvasTex(18, 7, (set) => {
    const C = { W: g(255), M: g(185), D: g(40) };
    const draw = (ox, rows) => rows.forEach((r, y) => [...r].forEach((ch, x) => { if (C[ch]) set(ox + x, y, C[ch]); }));
    draw(0, ['WW.....WW', 'WWW...WWW', 'WWWW.WWWW', '.WWWDWWW.', '.MMMDMMM.', '.MM.D.MM.', '.M..D..M.']);
    draw(9, ['..W...W..', '..WW.WW..', '..WW.WW..', '...WDW...', '...MDM...', '...MDM...', '....D....']);
  });
}
// 落葉 6×6
export function leafBit() {
  return canvasTex(6, 6, (set) => {
    ['..WW..', '.WWWM.', 'WWWMM.', 'WWMMMD', '.MMMD.', '...D..'].forEach((r, y) => [...r].forEach((ch, x) => { if (ch !== '.') set(x, y, g({ W: 255, M: 205, D: 140 }[ch])); }));
  });
}
// 煙團 16×16：alpha 由中心往外遞減，shader 用門檻讓它從邊緣消散
export function smokeTex() {
  return canvasTex(16, 16, (set) => {
    const r = rng(5);
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      const d = Math.hypot(x - 7.5, y - 7.5) / 8 + (Math.sin(x * 1.9) + Math.cos(y * 2.3)) * 0.05;
      if (d > 1) continue;
      const lit = (x + (15 - y)) < 13 ? 235 : (x + (15 - y)) < 20 ? 195 : 150;
      set(x, y, [lit, lit, lit, Math.max(10, Math.min(255, (1 - d) * 255 + (r() - 0.5) * 24))]);
    }
  });
}
// 樹皮 32×32（可平鋪）
export function barkTex() {
  return canvasTex(32, 32, (set) => {
    const r = rng(11);
    const pal = [[58, 40, 36], [78, 54, 44], [98, 70, 54], [44, 30, 30]];
    const col = new Array(32).fill(0).map(() => (r() * 3) | 0);
    for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
      let k = col[x];
      if (r() < 0.12) k = (r() * 4) | 0;
      if (x % 5 === 0 && r() < 0.8) k = 3;
      set(x, y, pal[k]);
    }
  }, { repeat: true });
}
// 草地 32×32
export function lawnTex() {
  return canvasTex(32, 32, (set) => {
    const r = rng(3);
    const pal = [[62, 104, 54], [78, 124, 58], [96, 142, 62], [52, 88, 52], [128, 160, 70]];
    for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
      const v = r();
      set(x, y, pal[v < 0.34 ? 0 : v < 0.66 ? 1 : v < 0.84 ? 2 : v < 0.96 ? 3 : 4]);
    }
  }, { repeat: true });
}
// 遮雨棚條紋 8×8
export function awningTex(a = [196, 62, 54], b = [240, 226, 196]) {
  return canvasTex(8, 8, (set) => {
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) set(x, y, x < 4 ? a : b);
  }, { repeat: true });
}
export function flat(col) {
  return canvasTex(2, 2, (set) => { for (let i = 0; i < 4; i++) set(i % 2, i >> 1, col); }, { repeat: true });
}

// 遠景剪影（山丘＋樹＋小屋燈）。layer: 0 最遠的山, 1 中丘, 2 近丘（帶樹與屋）
export function hillTex(layer, w = 1024, h = 128) {
  return canvasTex(w, h, (set) => {
    const r = rng(100 + layer);
    const ph = [r() * 6, r() * 6, r() * 6, r() * 6];
    const P = [
      { top: [150, 132, 176], bot: [190, 150, 170], amp: 34, base: 60, f: 1 },
      { top: [104, 100, 150], bot: [150, 122, 160], amp: 22, base: 78, f: 1.9 },
      { top: [58, 66, 104], bot: [92, 84, 124], amp: 12, base: 92, f: 3.1 },
    ][layer];
    const ridge = [];
    for (let x = 0; x < w; x++) {
      const u = x / w * 6.283;
      let y = P.base + Math.sin(u * P.f * 2 + ph[0]) * P.amp * 0.5 + Math.sin(u * P.f * 5 + ph[1]) * P.amp * 0.3 + Math.sin(u * P.f * 11 + ph[2]) * P.amp * 0.12;
      if (layer === 0) y -= Math.abs(Math.sin(u * 3.5 + ph[3])) * 26; // 山尖
      ridge.push(Math.round(y));
    }
    // 樹冠凸起
    if (layer > 0) for (let i = 0; i < w / (layer === 2 ? 7 : 12); i++) {
      const cx = (r() * w) | 0, rad = 2 + (r() * (layer === 2 ? 6 : 3) | 0);
      for (let dx = -rad; dx <= rad; dx++) { const x = (cx + dx + w) % w; const top = ridge[cx] - Math.round(Math.sqrt(rad * rad - dx * dx) * 1.2); if (top < ridge[x]) ridge[x] = top; }
    }
    for (let x = 0; x < w; x++) for (let y = ridge[x]; y < h; y++) {
      const t = Math.min(1, (y - ridge[x]) / 34);
      const lit = y - ridge[x] < 2 ? 1.16 : 1; // 稜線受光
      set(x, y, [0, 1, 2].map((k) => Math.min(255, (P.top[k] + (P.bot[k] - P.top[k]) * t) * lit)));
    }
    if (layer === 2) for (let i = 0; i < 46; i++) { // 小屋與燈
      const x = (r() * w) | 0, y = ridge[x] + 3 + (r() * 14 | 0);
      const roof = [112, 70, 84], wall = [150, 126, 140];
      for (let dx = 0; dx < 5; dx++) { set(x + dx, y, roof); set(x + dx, y + 1, wall); set(x + dx, y + 2, wall); }
      set(x + 1, y - 1, roof); set(x + 2, y - 1, roof); set(x + 3, y - 1, roof);
      if (r() < 0.7) set(x + 1 + (r() * 3 | 0), y + 1, [255, 214, 120]);
    }
  });
}
