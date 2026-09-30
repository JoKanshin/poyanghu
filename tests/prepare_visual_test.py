"""Create an isolated Godot test copy without touching the player's saved game."""
from pathlib import Path
import shutil
import tempfile
import sys
source = Path(__file__).resolve().parents[1]
target = Path(tempfile.mkdtemp(prefix="poyang-visual-test-"))
for name in ("scripts", "scenes", "assets", "fonts", "tests", "addons"):
    shutil.copytree(source / name, target / name)
shutil.copy2(source / "icon.svg", target / "icon.svg")
config = (source / "project.godot").read_text()
config = config.replace('config/name="保卫鄱阳湖"', 'config/name="Poyang Visual Test"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + target.name + '"')
config = config.replace('run/main_scene="res://scenes/main.tscn"', 'run/main_scene="res://tests/visual_smoke.tscn"')
(target / "project.godot").write_text(config)
print(target)
