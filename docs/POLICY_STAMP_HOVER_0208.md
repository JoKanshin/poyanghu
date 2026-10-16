# 0.2.8 政策盖章悬停提示

基于 Celikina/poyanghu 的 main，提交 `7e427c30feb9a7e43bb1d4ddb7643be101b0d605`。

政策力度卷轴中，鼠标停在可以交互、但当前没有盖章的方框上时，显示对应印章的浅色预览。预览直接复用该档位的 `SEALS` 纹理、尺寸和落章位置，RGB 保持原样，仅将透明度设为 28%，不播放动画、不切换档位、不触发音效。

当前已盖章的方框不显示预览。鼠标移出、盖章切换选中档位、方框禁用、冷却/结算锁定、选择器隐藏或其他界面遮挡时，预览消失。鼠标停留期间会检查交互状态，因此不必移动鼠标也能在冷却结束后恢复提示。预览本身不接收鼠标事件，不影响原有点击与盖章动画。

使用独立项目与独立用户目录验证，避免读取或改写玩家存档：

```bash
python3 tests/prepare_visual_test.py policy_stamp_hover /tmp/poyang-stamp-hover-test
/workspace/.cloud-setup/poyanghu/godot.sh --headless --path /tmp/poyang-stamp-hover-test --editor --import
/workspace/.cloud-setup/poyanghu/godot.sh --headless --path /tmp/poyang-stamp-hover-test
```

`POLICY_STAMP_HOVER: 26 checks, 0 failures`。覆盖实际鼠标输入、两个未选中档位、纹理与透明度、正式印章保持不变、已盖章档位、直接禁用/恢复、冷却/结算锁定、点击穿过预览、缩放对齐、遮挡、移出与隐藏。
