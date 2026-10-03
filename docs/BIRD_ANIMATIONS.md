# 候鸟动作图集 v2

五种鸟各使用一张透明 4×4 图集，共 80 个姿势。图片由内置 imagegen 生成，原创绘制；没有复制第三方鸟类素材。参考 Etienne Pouvreau 的 Pixel Duck Anim SpriteSheet 的简约侧视表现，物种外形参考国际鹤类基金会和 Cornell/eBird 的识别资料。

| 游戏物种 | 图集 | 外形特征 |
|---|---|---|
| 白鹤 | bird-baihe-v2.png | 白色细长体形、红面、黑色翼端、长粉红腿 |
| 东方白鹳 | bird-dongfangbaihuan-v2.png | 白头白身、黑飞羽、长黑喙、红腿 |
| 小天鹅 | bird-xiaotiane-v2.png | 白色圆身、弯颈、黑喙黄基、短黑足 |
| 白枕鹤 | bird-baizhenhe-v2.png | 灰身、白色后颈条纹、红眼周、粉红长腿 |
| 雁类 | bird-yanlei-v2.png | 以白额雁为代表：棕灰身、白额、橙粉喙、橙足 |

帧从 0 开始，按每行从左到右排列：

| 帧 | 动作 |
|---|---|
| 0–1 | 待机 |
| 2–5 | 行走 |
| 6–8 | 低头、啄食、抬头 |
| 9–12 | 振翅飞行 |
| 13 | 收翅休息 |
| 14 | 起飞 |
| 15 | 落地 |

`pixel_wetland.gd` 依据物种和动作读取图集，单独记录每只鸟的动作时间。起飞与降落先播放过渡姿势，再进入循环。鸟类始终直立，仅根据摄像机投影后的运动方向水平翻转，脚部锚点为单帧高度的 87.5%。开启减少动态效果时显示各动作的固定姿势。

原来的 `bird-actions.png` 与其生成脚本保留供对照，新图集由 imagegen 生成，不由 `build_ecology_sprites.py` 覆盖。完整生成提示保存在 `bird-generation-prompts.json`。

游戏内鸟类显示尺寸统一乘以 0.65：普通鸟约 30×30，天鹅约 32.5×32.5 逻辑像素。菜单拉远时再随摄像机一起缩小，脚部位置始终跟随地面投影。

参考：

- https://smolware.itch.io/pixel-geese-anim-spritesheet
- https://savingcranes.org/species/siberian-crane/
- https://savingcranes.org/species/white-naped-crane/
- https://ebird.org/species/oristo1
- https://www.allaboutbirds.org/guide/Tundra_Swan/id
- https://ebird.org/species/gwfgoo
