"""Prepare an isolated 60-second walkthrough build and matching human narration."""
from pathlib import Path
import json, shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/demo-20261020'
PROJECT = OUT / 'project'
DELIVERY = OUT / '交付'
PROJECT.mkdir(parents=True, exist_ok=True)
DELIVERY.mkdir(exist_ok=True)
for name in ['scripts', 'scenes', 'assets', 'licenses', 'fonts', 'data', 'audio']:
    if (ROOT / name).exists():
        shutil.copytree(ROOT / name, PROJECT / name, dirs_exist_ok=True)
for name in ['project.godot', 'export_presets.cfg', 'icon.png', 'icon.ico']:
    shutil.copy2(ROOT / name, PROJECT / name)
p = PROJECT / 'project.godot'
s = p.read_text(encoding='utf-8')
s = '\n'.join(line for line in s.splitlines() if '_mcp_game_helper=' not in line)
s = s.replace('enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")', 'enabled=PackedStringArray()')
s = s.replace('config/custom_user_dir_name.windows="Godot/app_userdata/保卫鄱阳湖"', 'config/custom_user_dir_name.windows="Godot/app_userdata/PoyangDemo01212"')
s = s.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="PoyangDemo01212"')
s += '\n[editor]\nmovie_writer/fps=30\nmovie_writer/mjpeg_quality=0.88\n'
p.write_text(s, encoding='utf-8')
p = PROJECT / 'export_presets.cfg'
s = p.read_text(encoding='utf-8').replace('custom_features=""', 'custom_features="demo_build"', 1)
s = s.replace('application/file_version="0.2.11.1"', 'application/file_version="0.2.12.3"').replace('application/product_version="0.2.11.1"', 'application/product_version="0.2.12.3"')
s = s.replace('assets/motion/*.json', 'assets/motion/*.json,assets/demo/*.json')
p.write_text(s, encoding='utf-8')
timeline = json.loads((ROOT / 'assets/demo/timeline.json').read_text(encoding='utf-8'))
def stamp(t):
    return f'{int(t)//60:02d}:{int(t)%60:02d}'
def srt_stamp(t):
    return f'00:{int(t)//60:02d}:{int(t)%60:02d},{round((t%1)*1000):03d}'
md = ['# 《鄱阳归翎》一分钟演示旁白（56 秒）', '', '总长 56 秒，约 250 字；由真人朗读，不包含 AI 配音。', '', '画面默认显示固定位置、固定尺寸的分段旁白字幕，换句只换文字，不添加上下黑边。F2 可选打开独立提词窗，默认不弹出。', '', '| 时间 | 画面与运镜 | 朗读内容 |', '| --- | --- | --- |']
srt = []
for i, shot in enumerate(timeline['shots'], 1):
    md.append(f"| {stamp(shot['at'])}–{stamp(shot['until'])} | {shot['title']} | {shot['text']} |")
for i, line in enumerate(timeline['captions'], 1):
    srt.append(f"{i}\n{srt_stamp(line['at'])} --> {srt_stamp(line['until'])}\n{line['text']}\n")
md += ['', '## 操作', '', '- 主菜单右上角点击“一分钟实机演示”，入口立即隐藏；约 56 秒自动结束并返回主菜单。', '- 空格同步暂停或继续提词、游戏和 BGM，便于真人练习。', '- F2 显隐提词窗，F3 显隐画面字幕，F5 从头重播，Esc 返回菜单。', '- 参考上传的一分钟评审视频：深色底、金色标题，开头介绍玩法，结尾三栏总结，中段使用稳定的完整游戏画面。字幕固定在画面内顶部，不移位、不闪烁。', '- 音乐：正常段 theme；31 秒干旱爆发切危机曲，补水恢复后回到 theme。保留原生操作音效。', '- 画面使用真实游戏场景、卡牌执行和结算；为一分钟演示使用固定种子、手牌、预算及指定危机，不代表正常游玩的自然抽牌或难度。', '- 演示使用独立存档目录 PoyangDemo01212，不修改正式版玩家进度。', '- 向上拖牌后先在原有已打出区展示完整牌面，再自动归入原尺寸的待执行木板；不放大木板。', '- SRT 与游戏内字幕共用同一份时间表，可用于后期调整。']
(DELIVERY / '旁白与镜头时间表.md').write_text('\n'.join(md)+'\n', encoding='utf-8')
(DELIVERY / '旁白时间码.srt').write_text('\n'.join(srt), encoding='utf-8-sig')
print('Prepared demo:', PROJECT)
print('Narration characters:', sum(len(s['text']) for s in timeline['shots']))
