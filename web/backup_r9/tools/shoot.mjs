// node tools/shoot.mjs <輸出前綴> [query] [--n=3] [--crop=x,y,w,h ...]   需先 npm run dev（埠 5473）
import { chromium } from 'playwright-core';
import os from 'node:os';
import fs from 'node:fs';
const args = process.argv.slice(2);
const out = args[0] ?? 'shot', query = args[1] && !args[1].startsWith('--') ? args[1] : '';
const n = +(args.find((a) => a.startsWith('--n='))?.slice(4) ?? 1);
const crops = args.filter((a) => a.startsWith('--crop=')).map((a) => a.slice(7).split(',').map(Number));
const dir = fs.readdirSync(`${os.homedir()}/.cache/ms-playwright`).filter((d) => /^chromium-\d+$/.test(d)).sort().pop();
const exe = `${os.homedir()}/.cache/ms-playwright/${dir}/chrome-linux64/chrome`;
const browser = await chromium.launch({ executablePath: exe, args: ['--use-gl=angle', '--use-angle=gl-egl', '--ignore-gpu-blocklist', '--enable-gpu'] });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
const errs = [];
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errs.push(m.text()); });
page.on('pageerror', (e) => errs.push('PAGEERROR ' + e.message));
await page.goto(`http://127.0.0.1:${process.env.PORT ?? 5473}/${query}`);
try { await page.waitForFunction(() => (window.__frames || 0) > 200, null, { timeout: 30000 }); } catch { errs.push('timeout waiting frames'); }
for (let i = 0; i < n; i++) {
  if (i) await page.waitForTimeout(2000);
  await page.screenshot({ path: n > 1 ? `${out}_${i + 1}.png` : `${out}.png` });
}
for (const [i, c] of crops.entries()) await page.screenshot({ path: `${out}_crop${i + 1}.png`, clip: { x: c[0], y: c[1], width: c[2], height: c[3] } });
console.log('gpu:', await page.evaluate(() => window.__gpu), 'fps:', await page.evaluate(() => window.__fps?.toFixed(1)));
console.log([...new Set(errs)].slice(0, 12).join('\n') || 'no errors');
await browser.close();
