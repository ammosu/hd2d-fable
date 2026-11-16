#!/bin/bash
# 截圖：./shoot.sh            → shots/godot/r11/full_1..3.png ＋ 2 張特寫
#       ./shoot.sh --tag=x …  → shots/godot/r11/compare_x.png（單張，可加 --no-fog --no-beams --no-dof --no-refl）
cd "$(dirname "$0")"
timeout -k 5 60 godot --path . --resolution 1920x1080 -- --shots "$@" 2>&1 | grep -v -E '^(Godot Engine|Vulkan|$)' 
