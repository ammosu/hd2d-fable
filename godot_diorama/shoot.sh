#!/bin/bash
# 截圖：./shoot.sh → ../shots/godot_diorama/full_1..3.png ＋特寫（--out=r3 存到子資料夾）
#       ./shoot.sh --tag=x [--no-dof --no-fog --no-shadow --no-refl --no-leaves --mask --top] → compare_x.png（加 --work 改存 tools/work/）
# 視窗被遮住或螢幕休眠時 Wayland 會停止送出畫格，截圖會卡住；所以每次限時 40 秒，沒看到「done」就重試（最多 4 次）。
cd "$(dirname "$0")"
for try in 1 2 3 4; do
  out=$(timeout -k 5 40 godot --path . --resolution 1920x1080 -- --shots "$@" 2>&1 | grep -v -E '^(Godot Engine|Vulkan|$)')
  echo "$out"
  echo "$out" | grep -q "^done" && exit 0
  echo "retry $try"
done
exit 1
