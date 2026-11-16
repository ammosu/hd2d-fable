#!/usr/bin/env python3
"""用 codex CLI 生像素風素材。 python3 tools/gen.py name1 name2 ...（不給名字 = 產生所有缺少的）
原檔存 tools/raw/<name>.png；清單在 tools/assets.json"""
import json, os, subprocess, sys, shutil, time
from concurrent.futures import ThreadPoolExecutor
T = os.path.dirname(os.path.abspath(__file__))
RAW, WORK = os.path.join(T, 'raw'), os.path.join(T, 'work')
A = json.load(open(os.path.join(T, 'assets.json')))
COMMON = {
 'image': '這是像素風（pixel art）遊戲用的單張貼圖（不需要平鋪，整張畫滿、不留邊框與空白）：嚴格的像素畫，每個「點陣」都是同樣大小的正方形色塊，邊緣銳利、沒有抗鋸齒、沒有模糊漸層，手繪像素畫質感、細節密度高。光線平均柔和（之後由 3D 引擎打光），沒有投影、沒有暗角、沒有文字。',
 'sprite': '這是 2D 像素風（pixel art）遊戲用的透明元件：PNG，背景必須是真正透明的 alpha（不要白底、不要棋盤格）。嚴格的像素畫：每個「點陣」都是同樣大小的正方形色塊，邊緣銳利、沒有抗鋸齒、沒有漸層模糊、沒有半透明，用色有限（約 16～24 色），手繪像素畫質感、有清楚的明暗色階與深色輪廓。光線平均柔和（之後由 3D 引擎打光），不要畫地面、不要投影、不要任何文字或浮水印。元件置中、四周留一點空白。',
 'tile': '這是像素風（pixel art）遊戲用的「可無縫平鋪」材質貼圖：正方形，正面平視、無透視，嚴格的像素畫：每個「點陣」都是同樣大小的正方形色塊，邊緣銳利、沒有抗鋸齒、沒有模糊漸層，用色有限（約 12～16 色），手繪像素畫質感。光線平均柔和、沒有投影、沒有暗角、沒有文字。上下左右四個邊緣必須能無縫接合。',
}
def gen(name):
    a = A[name]; d = os.path.join(WORK, name)
    shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    style = '附圖是這個遊戲的美術定稿，請讓素材的畫風、用色（低飽和、偏暗、帶紫灰的中間調）、點陣大小與細節密度對齊附圖，但只畫下面指定的素材本身，不要重畫整個場景。' if a.get('ref') else ''
    p = f"請用你的圖片生成功能產生一張圖片。{style}{COMMON[a['kind']]}內容：{a['prompt']}\n完成後把圖片存成目前目錄下的 ./{name}.png（只要這一個檔案，不要做其他事）。"
    t0 = time.time()
    try:
        r = subprocess.run(['codex', 'exec', '-s', 'workspace-write', '--skip-git-repo-check', '-C', d] + (['-i', __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '/../../target/godot/target.png'] if a.get('ref') else []), input=p.encode(), stdout=open(os.path.join(d, 'out.log'), 'wb'), stderr=subprocess.STDOUT, timeout=480)
        rc = r.returncode
    except subprocess.TimeoutExpired:
        rc = 'timeout'
    out = os.path.join(d, name + '.png'); ok = os.path.exists(out)
    if ok: shutil.copy(out, os.path.join(RAW, name + '.png'))
    print(f"{'ok  ' if ok else 'FAIL'} {name} rc={rc} {time.time()-t0:.0f}s", flush=True)
names = sys.argv[1:] or [n for n in A if not os.path.exists(os.path.join(RAW, n + '.png'))]
with ThreadPoolExecutor(4) as ex: list(ex.map(gen, names))
