#!/bin/bash
# 截圖：./shoot.sh → ../shots/godot_diorama/full_1..3.png ＋特寫（--out=r3 存到子資料夾）
#       ./shoot.sh --tag=x [--no-dof --no-fog --no-shadow --no-refl --no-leaves --mask --top] → compare_x.png（加 --work 改存 tools/work/）
# 視窗被遮住或螢幕休眠時 Wayland 會停止送出畫格，截圖會卡住；所以每次限時 40 秒，沒看到「done」就重試（最多 4 次）。
cd "$(dirname "$0")"
for try in 1 2 3 4; do
  # pilot：預設在虛擬螢幕（Xvfb）執行，不會在實體桌面跳出視窗、也不受螢幕鎖定或被別的視窗蓋住影響（Vulkan 仍用實體顯示卡）。
  # 虛擬螢幕下的 fps 讀數（約 37）不能當效能數據；要在實體桌面拍：SHOOT_REAL=1 ./shoot.sh …
  if [ -n "$SHOOT_REAL" ]; then run=(godot ${GODOT_DD:+--display-driver $GODOT_DD}); else run=(xvfb-run -a -s "-screen 0 1920x1080x24" godot --display-driver x11); fi
  out=$(timeout -k 5 40 "${run[@]}" --path . --resolution 1920x1080 -- --shots "$@" 2>&1 | grep -v -E '^(Godot Engine|Vulkan|$)')
  echo "$out"
  echo "$out" | grep -q "^done" && exit 0
  echo "retry $try"
done
exit 1
