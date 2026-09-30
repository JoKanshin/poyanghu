# 鄱阳湖 UI 与像素湿地改造

对局地图已更新为按地理坐标绘制的鄱阳湖底图，并放大显示湖区；主菜单仍使用原视觉改造的湿地插画。鸟类、植物、房屋和彩蛋沿用旧版游戏的视觉触发逻辑，详见 [地形说明](TERRAIN_MAP.md)。下文其余场景描述记录上午的 UI 改造。

基线：`master` 的 `8b0807f7fcecb072765396b04a11ac8b8a992093`。
分支：`feat/poyang-pixel-ui`。

## 本次变化

- 原创湿地像素场景替换原运行时 3D 沙盘：芦苇洲、浅滩、赣鄱民居、码头和渔舟。
- 水波、微风、候鸟、鱼群与渔舟的轻量动画；背景以最近邻过滤呈现，动态层以 24 Hz 刷新，卡牌和 UI 仍逐帧平滑插值。
- 场景只读取生态状态：五类鸟群分别对应原物种数量；鱼群、芦苇、莲、人工浮岛、居民点与社区亮灯分别读取既有状态；水位、水质、植被及季节影响场景色彩与浅滩表现。
- 对局底图由公开地理数据绘制，水深色带为游戏表现而非实测；动态生物、植物、房屋及色彩反馈用于展示状态，不改变模拟结果。
- 深湖绿面板、暖纸色卡牌、薄荷色边框、金色主操作按钮和统一的弹窗/设置/牌库样式。
- 六幅原创类别插画、原创白鹤牌背，保留卡牌 122×165 的动画坐标约定；长卡名、类别、费用仍显示，完整效果沿用悬停和详情。
- 保留扇形发牌、透视牌库、排序、结算节拍与滑入滑出，增加手牌轻微指针倾斜和统一按钮反馈。
- 修正卡牌取消选中后预算标签未即时更新、快速补全文字时打字动画吞点击、重复选中产生多个发光 Tween 的界面问题。
- 使用 Compatibility 渲染器，降低纯 2D 场景的图形要求；保留项目的 Godot 4.7 版本和现有编辑器插件。

## 保持不变

`game_state.gd`、`talents.gd`、`achievements.gd` 与基线逐字相同。卡牌费用与效果、四档难度、行动位、结转利息、事件、物种模拟、危机、成就及存档格式不变。视觉层不调用游戏随机数、不写入 GameState；卡面插画由卡牌 ID 的稳定哈希选择。

旧的 3D 构建辅助函数保留在 `main.gd`，但不再在 `_ready` 中构建；新场景由 `pixel_wetland.gd` 管理。原 `_update_3d` 信号入口保留，以维持结算期间冻结、结算后统一更新的既有时序。

## 打开游戏

用 **Godot 4.7 stable** 导入根目录 `project.godot`，等待素材导入后运行 `scenes/main.tscn`（F6）或项目（F5）。无需额外字体或在线美术资源。

原 Windows 导出预设继续保留，需要安装与 Godot 版本一致的 Windows 导出模板。本次验证为 macOS 上的引擎运行，没有声称完成 Windows 打包或实体 Windows 测试。

## 测试

先创建隔离副本，避免影响玩家存档：

```sh
python3 tests/prepare_visual_test.py
```

记下打印的目录，再运行（把 GODOT 替换为自己的 Godot 4.7 可执行文件）：

```sh
GODOT --headless --path <隔离目录> --editor --import --quit
GODOT --path <隔离目录>
```

可选设置 `POYANG_SCREENSHOT_DIR` 为已存在的截图目录；无图形环境运行时跳过截图。
隔离副本使用独立的用户数据目录，主入口为 `tests/visual_smoke.tscn`。

已在 Godot **4.7.stable.official.5b4e0cb0f**、macOS / Apple A18 Pro、Compatibility 渲染器实测，输出 `VISUAL_SMOKE: PASS (0 failures)`。覆盖：

地形合并及旧版生态表现接入后，又在 Godot **4.7.2.stable.official.ed1daf0bf** 上运行隔离测试，输出 `VISUAL_SMOKE: PASS (0 failures)`，并目视检查更新后的对局画面。

- 主菜单 → 难度 → 指定种子新局；
- 发牌、全部卡牌最小尺寸与长名称排版；
- 选牌/取消与预算、投入档位锁定；
- 牌库、紧急调度面板、暂停和设置；
- 实际行动执行 → 结算演出 → 下一季 → 地图状态同步；
- 存档/读取；960×540、1280×720、1600×900 窗口；
- `git diff --check` 及三个数值/规则文件与基线无差异。

## 素材与维护

- `assets/art/poyang-wetland.png`：主菜单湿地插画。
- `assets/art/poyang-terrain-base.png`：对局中的地理地形底图。
- `assets/houses/house1.png` 至 `house4.png`：沿用旧版村落房屋素材。
- `assets/art/conservation-cards.png`：3×2 卡牌插画图集。
- `assets/art/wetland-sprites.png`：4×2 透明环境图集；运行时使用鱼、芦苇和舟船格。
- `assets/art/wetland-birds.png`：保留莲叶荷花素材。
- `assets/art/bird-actions.png`：原创五物种九帧动作图集，按状态播放站立、行走、啄食、飞行和栖息，并随移动方向转向。
- `assets/art/floating-island.png`、`assets/art/shore-tree.png`：自行绘制的像素浮动地块与树木。
- `assets/art/guardian-card-back.svg`：原创界面牌背。
- `scripts/visual_theme.gd`：配色、卡面、按钮与面板样式。
- `docs/art-manifest.json`：生成提示词、原创逐帧素材及参考链接。

视觉方向参考 Balatro 的卡牌反馈与层次、Stardew Valley 的温暖像素场景；没有打包两款参考游戏的贴图、角色、地图或商标。背景图、插画、透明图集由内置 image_gen 生成，牌背由本项目编写；原仓库已有素材及字体许可保持原状。鸟类图集为风格化教育游戏插画，不代替物种鉴定图谱。
