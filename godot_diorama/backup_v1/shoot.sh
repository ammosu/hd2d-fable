#!/bin/bash
# 截圖：./shoot.sh → ../shots/godot_diorama/full_1..3.png ＋特寫
#       ./shoot.sh --tag=x [--no-dof --no-fog --no-shadow --no-refl --no-leaves --mask --top] → compare_x.png（加 --work 改存 tools/work/）
cd "$(dirname "$0")"
timeout -k 5 90 godot --path . --resolution 1920x1080 -- --shots "$@" 2>&1 | grep -v -E '^(Godot Engine|Vulkan|$)'
