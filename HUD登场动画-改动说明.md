# 开局 HUD 登场动画 · 改动说明

**日期**：2026-09-26
**改动文件**：`scripts/main.gd`（只有这一个文件，一处新增函数 + 一行调用）
**需求原话**：「给生态指标和回合ui在游戏开始时设计一个从屏幕外到现在位置的动画吧」

---

## 一、改了什么

### 1. 新增 `_play_hud_enter()`（在 `_make_metric_row` 之前）

```gdscript
## 开局登场：左侧「回合 / 资金」面板从屏幕左外滑入，右侧「生态指标」面板从右外滑入。
## 方向与 _slide_side_panels 保持一致，落点就是两块面板的常驻位置。
## 手感：QUART + EASE_OUT（起步快、收尾稳），右侧晚 0.08s 出发，两侧同时淡入。
func _play_hud_enter() -> void:
	if left_panel == null or right_panel == null:
		return
	const L_HOME_L := 6.0        # 左面板常驻位置
	const L_HOME_R := 210.0
	const R_HOME_L := -190.0     # 右面板常驻位置（锚在屏幕右缘，负值向左）
	const R_HOME_R := -6.0
	const GAP := 12.0            # 屏幕外的额外间隙
	const DUR := 0.55            # 滑入时长（秒）
	const LAG := 0.08            # 右侧延后出发

	# 先瞬移到屏幕外（同帧完成，渲染时看不到中间状态）
	left_panel.offset_left = -(L_HOME_R - L_HOME_L) - GAP
	left_panel.offset_right = -GAP
	right_panel.offset_left = GAP
	right_panel.offset_right = (R_HOME_R - R_HOME_L) + GAP
	left_panel.modulate.a = 0.0
	right_panel.modulate.a = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(left_panel, "offset_left", L_HOME_L, DUR)
	tw.tween_property(left_panel, "offset_right", L_HOME_R, DUR)
	tw.tween_property(left_panel, "modulate:a", 1.0, DUR * 0.7)
	tw.tween_property(right_panel, "offset_left", R_HOME_L, DUR).set_delay(LAG)
	tw.tween_property(right_panel, "offset_right", R_HOME_R, DUR).set_delay(LAG)
	tw.tween_property(right_panel, "modulate:a", 1.0, DUR * 0.7).set_delay(LAG)
```

### 2. 在 `_on_start_pressed()` 末尾加一行调用

```gdscript
	_hide_menu()
	GameState.reset_game()
	_update_hud()
	_update_3d()
	_play_hud_enter()      # 开局登场：两块面板从屏幕外滑入
```

---

## 二、设计要点

| 元素 | 做法 | 为什么 |
|---|---|---|
| 起点 | 左面板整体挪到屏幕左外（`offset_right = -12`），右面板挪到屏幕右外（`offset_left = 12`） | 真正的「屏幕外」，不是贴边 |
| 方向 | 左从左进、右从右进 | 与结算时 `_slide_side_panels(true/false)` 的进出方向一致，前后观感统一 |
| 缓动 | `TRANS_QUART` + `EASE_OUT` | 起步快、收尾稳，滑入带一点「落定」的从容感 |
| 错开 | 右侧延迟 0.08s 出发 | 两块同时滑会显得呆板；错开后视线先左后右 |
| 淡入 | `modulate:a` 0 → 1，用时 `DUR * 0.7` | 只靠位移会像「硬贴」，叠一层淡入更柔和 |
| 瞬移 | 先同帧把 offset 设到屏幕外，再建 Tween | 玩家看不到「本来在位、突然消失」的一帧闪烁 |

面板尺寸来自现状（左 `6 / 210`，右 `-190 / -6`），所以落点不需要重新测量——`_build_ui()` 里定的就是常驻位置。

---

## 三、验证结果

在「点开始游戏」的瞬间连拍，逐帧确认（截图 `screenshots_poyanghu_new/15_HUD滑入_连拍6帧.png`）：

| 时刻 | 画面 |
|---|---|
| +0.04s | 还在种子页（点击刚发出） |
| +0.07s | 菜单消失，**两块面板完全不在画面内**（屏幕外） |
| +0.10s | 左面板从左缘露头、右面板从右缘露头，透明度仍低 |
| +0.14s / +0.18s | 继续向内滑动 |
| +0.21s | 已接近落位（左能看到「回合/年份」，右「生态指标」成形） |
| 动画结束（+1.5s） | 两块面板精确落回常驻位置，无偏移/越界/半透明残留 |

终态对比见图 `16_HUD滑入_前后对比.png`（上=屏幕外那一帧，下=落位后）。

编译：`godot --headless --quit-after 200` 零错误。

---

## 四、想调整的时候

全部参数都在 `_play_hud_enter()` 顶部那几个 `const` 里：

| 想改什么 | 改哪个 |
|---|---|
| 滑入快慢 | `DUR := 0.55`（秒） |
| 左右出发的时间差 | `LAG := 0.08`（`0.0` = 同时出发） |
| 起点离屏幕多远 | `GAP := 12.0`（越大，起手越远） |
| 淡入的相对时长 | `DUR * 0.7` 这个系数 |
| 缓动手感 | `set_trans` / `set_ease`（想更「弹」可以试 `TRANS_BACK` + `EASE_OUT`） |
| 完全关掉这个动画 | 删掉 `_on_start_pressed()` 里那行 `_play_hud_enter()` |

---

## 五、备注

1. **每次开局都会播**：点「开始游戏」进游戏时触发；一局结束后回到主菜单再来一局，同样会播。
2. **和结算滑出不冲突**：结算时 `_slide_side_panels(true)` 把面板收回屏幕外，下一回合 `_enter_allocate()` 里 `_slide_side_panels(false)` 再弹回来——那是回合间的动画，与开局的登场动画是两条独立路径，互不干扰。
3. **中途快速操作不会留下歪掉的面板**：因为每次进入游戏都先把 offset 直接设到屏幕外，不依赖上一帧的状态。
4. 回滚：删掉 `_play_hud_enter()` 函数和 `_on_start_pressed()` 里那一行即可。
