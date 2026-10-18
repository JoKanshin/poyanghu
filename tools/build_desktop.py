"""Prepare a release project without development helpers; preserve Windows saves."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'build/windows/project'
PROJECT.mkdir(parents=True, exist_ok=True)
for name in ['scripts', 'scenes', 'assets', 'licenses', 'fonts', 'data', 'audio']:
    if (ROOT / name).exists():
        shutil.copytree(ROOT / name, PROJECT / name, dirs_exist_ok=True)
for name in ['project.godot', 'export_presets.cfg', 'icon.png', 'icon.ico']:
    shutil.copy2(ROOT / name, PROJECT / name)
p = PROJECT / 'project.godot'
s = p.read_text(encoding='utf-8')
s = '\n'.join(line for line in s.splitlines() if '_mcp_game_helper=' not in line)
s = s.replace('enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")', 'enabled=PackedStringArray()')
p.write_text(s, encoding='utf-8')
print('Prepared Windows release project:', PROJECT)
