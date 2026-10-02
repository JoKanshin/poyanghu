# 队友数值合并核对

本次基于本地 `ad6c0dd`，读取队友仓库 `QQQiZZZhe/zhengjiupoyanghu` 的 `main` 分支，合入提交 `af8e15988c8184405aa693839041cce6b08e5763` 的玩法定价修改。共同基线为 `7fa20fa`。

## 合入范围

- 44 张行动卡中 39 张标准价改变，所有标准价为 10 的倍数；总价 1473 → 1430 万。
- `game_state.gd` 中全部非价格文本与合并前逐字一致；卡牌的其他字段也逐项核对一致，包括 ID、类别、效果、延迟、季节与标签。
- 基础 / 有效 / 深度倍率及天赋折扣函数保持原样，卡面与实际扣费仍统一调用 `tier_cost()`。
- 队友的透视地图、房屋阴影与项目配置不合入，保留当前 45 度 Camera3D、动画鸟类、主菜单镜头、河道、船只及植被。
- 更新日志仅说明此次定价合并。队友文档中建议弃用旧存档，但代码没有对应的格式变更或版本拦截；本次保留原存档读取规则，读档后按新价格继续。

## 价格变更（标准档，单位：万）

| 卡牌 | ID | 合并前 | 合并后 |
| --- | --- | ---: | ---: |
| 碟形湖控水 | `water_control` | 39 | 40 |
| 草种库保育 | `seed_bank` | 33 | 30 |
| 水质监测与病害防治 | `water_monitor` | 22 | 20 |
| 外来物种清除 | `invasive_clear` | 31 | 30 |
| 候鸟食堂营建 | `bird_canteen` | 19 | 20 |
| 应急救护 | `rescue` | 11 | 10 |
| 社区补偿 | `community_comp` | 29 | 30 |
| 转产投资 | `industry_switch` | 28 | 30 |
| 社区共管与护鸟队 | `guard_team` | 25 | 20 |
| 科普宣传与公众参与 | `education` | 18 | 20 |
| 执法巡逻 | `patrol` | 19 | 20 |
| 生态补水（引江济湖） | `water_replenish` | 49 | 50 |
| 蓄水保水工程 | `water_storage` | 33 | 30 |
| 闸坝联合调度 | `water_schedule` | 33 | 30 |
| 退田还湿（湿地生态修复） | `wetland_restore` | 31 | 40 |
| 人工浮岛（生态浮床） | `floating_island` | 35 | 30 |
| 底泥清淤疏浚 | `dredge` | 27 | 30 |
| 越冬栖息地保护 | `habitat_protect` | 27 | 20 |
| 生态旅游与观鸟经济 | `ecotourism` | 31 | 30 |
| 野生动物致害保险 | `damage_insurance` | 32 | 30 |
| 生态产品认证与助销 | `eco_brand` | 26 | 30 |
| 增殖放流 | `fish_restock` | 26 | 20 |
| 鱼类产卵场修复 | `spawning_ground` | 43 | 40 |
| 智慧巡护（无人机遥感） | `smart_patrol` | 25 | 20 |
| 湿地保护立法 | `wetland_law` | 33 | 40 |
| 封洲禁牧 | `grazing_ban` | 11 | 10 |
| 社区水权共管 | `water_comanage` | 44 | 40 |
| 社区污水共治 | `sewage_comanage` | 47 | 50 |
| 社区渔市共营 | `fish_market` | 44 | 40 |
| 候鸟友好社区 | `bird_friendly` | 44 | 40 |
| 渔民转产培训 | `fisher_retrain` | 42 | 40 |
| 生态管护公益岗 | `eco_jobs` | 41 | 40 |
| 生态搬迁安置 | `eco_resettle` | 42 | 40 |
| 灌江纳苗 | `sluice_fry` | 42 | 40 |
| 迁徙廊道管理 | `migration_corridor` | 42 | 40 |
| 湖区清障执法 | `obstruction_clear` | 42 | 40 |
| 湖长制考核 | `lake_chief` | 41 | 40 |
| 水工程鱼道建设 | `fishway` | 44 | 40 |
| 采砂监管 | `sand_mining` | 42 | 40 |

## 数值验证

- `tools/verify_prices.gd`：180 项通过，44 张卡的三个投入档与三种难度的资金流水保持整数万。
- `tools/verify_funding.gd`：15 项通过，拨款阈值、回合拨款与序列化往返正常。
- `tools/balance_scan.py --tiers effective`：有效档的套利 / 碾压计数均为 0，与原版一致。
- `tools/balance_scan.py`：全部三个档位计数为套利 2 / 碾压 1，与原版计数一致；最大节约额从 3 万变为 5 万，具体组合也发生变化。这是按六项指标与延迟折算的静态判据，不覆盖标签、季节、物种及知识点价值；本次按用户要求保留队友定价，未追加重新平衡。
- `tests/visual_smoke.gd`：`VISUAL_SMOKE: PASS (0 failures)`，卡面、选牌预算、执行行动、结算、下一季、存读档与窗口缩放均通过；图形运行错误日志为空。
