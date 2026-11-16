# HD-2D 運河小鎮・黃昏（網頁版）

啟動（一行）：

```
cd ./web && npm install && npm run dev
```

然後開 http://127.0.0.1:5473/ ，開啟即見畫面（固定 1920×1080，隨視窗等比縮放；沒有 UI）。
視窗不是 1920×1080 時會非整數縮放、像素變軟，請按 F11 全螢幕看。

截圖（需先啟動上面的伺服器；用本機 Playwright 的 Chromium＋NVIDIA GPU）：

```
node tools/shoot.mjs ../shots/web/r7/full --n=3      # 3 張相隔 2 秒
node tools/shoot.mjs out "?novol"                 # 對照開關：?novol ?noreflect ?nodof ?nobloom ?nofg
node tools/shoot.mjs out "?view=low"              # 看 640×360 原始像素層（另有 vol / rw / rs / fg / dof / bloom）
```

素材：`node tools/codex_gen.mjs`（codex 生圖 → codex_work/raw）→ `python3 -I tools/post.py`（縮成真正的低解析像素圖 → public/tex）。

量測亮度百分位：`python3 -I tools/measure.py ../shots/web/r7/full_1.png`

第七輪素材：`node tools/codex_gen.mjs --manifest=./assets7.mjs --ref=<目標圖>` → `python3 -I tools/post.py && python3 -I tools/post7.py`。
三階明度對照：`python3 -I tools/tones.py out.png 標籤=圖 ...`
