// node tools/codex_gen.mjs [--only=a,b] [--par=5]   用 codex CLI 生像素風素材到 codex_work/raw/
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { ASSETS } from './assets.mjs';
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const RAW = path.join(ROOT, 'codex_work/raw');
const WORK = path.join(ROOT, 'codex_work/run');
fs.mkdirSync(RAW, { recursive: true });
const opt = Object.fromEntries(process.argv.slice(2).filter((a) => a.startsWith('--')).map((a) => a.slice(2).split('=')).map(([k, v]) => [k, v ?? true]));
const only = opt.only ? new Set(opt.only.split(',')) : null;
const PAR = +(opt.par ?? 5);
const STYLE = '風格：手繪「像素藝術（pixel art）」，像 16 位元時代的日式 RPG 與現代 HD-2D 遊戲的點陣圖素材。必須是清楚、銳利、大顆的方形像素（整張圖大約只有 96×96 到 128×128 個「藝術像素」，每個藝術像素是邊緣銳利的純色方塊，不可以有反鋸齒、模糊、漸層或平滑陰影），有限的調色盤（每個材質 3～5 階明暗），用色塊和抖動表現質感。光照平均柔和，沒有明顯光源方向。不要任何文字、浮水印、邊框。';
const COMMON = {
  tile: '這是遊戲用的「可無縫平鋪」像素風材質貼圖：正方形，整張圖鋪滿材質，沒有透視、沒有投影、沒有暗角。上下左右四個邊緣必須能無縫接合，不要有單一顯眼會被看出重複的特徵。',
  sprite: '這是遊戲用的像素風透明元件（PNG，背景必須是真正透明的 alpha，不要白底、不要棋盤格）。元件置中、盡量佔滿畫面、四周只留一點空白，輪廓邊緣是乾淨的硬邊（像素不是半透明）。',
};
const prompt = (a) => `請用你的圖片生成功能產生一張圖片。${COMMON[a.kind]}${STYLE}\n內容：${a.prompt}\n完成後把圖片存成目前目錄下的 ./${a.name}.png（只要這一個檔案，不要做其他事）。`;
function gen(a) {
  return new Promise((res) => {
    const dir = path.join(WORK, a.name);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
    const t0 = Date.now();
    const p = spawn('codex', ['exec', '-s', 'workspace-write', '--skip-git-repo-check', '-C', dir], { stdio: ['pipe', 'ignore', fs.openSync(path.join(dir, 'err.log'), 'w')] });
    p.stdin.end(prompt(a));
    const timer = setTimeout(() => p.kill('SIGKILL'), 8 * 60 * 1000);
    p.on('exit', (code) => {
      clearTimeout(timer);
      const out = path.join(dir, `${a.name}.png`);
      const ok = fs.existsSync(out);
      if (ok) fs.copyFileSync(out, path.join(RAW, `${a.name}.png`));
      console.log(`${ok ? 'ok  ' : 'FAIL'} ${a.name} ${((Date.now() - t0) / 1000).toFixed(0)}s exit ${code}`);
      res(ok);
    });
  });
}
const todo = ASSETS.filter((a) => (only ? only.has(a.name) : !fs.existsSync(path.join(RAW, `${a.name}.png`))));
const queue = [...todo];
await Promise.all(Array.from({ length: PAR }, async () => { while (queue.length) await gen(queue.shift()); }));
console.log('done');
