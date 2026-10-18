"""Prepare an isolated Android build/QA project and a reusable local signing key."""
from pathlib import Path
import os, shutil, subprocess, secrets, json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/android'
PROJECT = OUT / 'project'
OUT.mkdir(parents=True, exist_ok=True)
(OUT / '.gdignore').touch()
PROJECT.mkdir(exist_ok=True)
for name in ['scripts', 'scenes', 'tests', 'assets', 'licenses', 'fonts', 'data', 'audio']:
    src, dst = ROOT / name, PROJECT / name
    if src.exists():
        shutil.copytree(src, dst, dirs_exist_ok=True)
for name in ['project.godot', 'export_presets.cfg', 'icon.png', 'icon.ico']:
    shutil.copy2(ROOT / name, PROJECT / name)
p = PROJECT / 'project.godot'
s = p.read_text(encoding='utf-8')
s = '\n'.join(x for x in s.splitlines() if '_mcp_game_helper=' not in x)
s = s.replace('enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")', 'enabled=PackedStringArray()')
s = s.replace('config/custom_user_dir_name.windows="Godot/app_userdata/保卫鄱阳湖"', 'config/custom_user_dir_name.windows="Godot/app_userdata/PoyangMobileQA"')
s = s.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="PoyangMobileQA"')
# Android uses its private app directory; the desktop preview is fully isolated.
s = s.replace('config/custom_user_dir_name="PoyangMobileQA"', 'config/custom_user_dir_name="PoyangMobileQA"\nconfig/custom_user_dir_name.android="PoyangMobile"')
p.write_text(s, encoding='utf-8')
credentials = OUT / 'signing-local.json'
keystore = OUT / 'poyang-mobile-release.keystore'
if not credentials.exists():
    credentials.write_text(json.dumps({'password': secrets.token_urlsafe(30), 'alias':'poyang-mobile'}, ensure_ascii=False), encoding='utf-8')
secret = json.loads(credentials.read_text(encoding='utf-8'))
jdk = Path('C:/android/jdk17/jdk-17.0.20.1+1')
if not keystore.exists():
    env = dict(os.environ, POYANG_KEY_PASSWORD=secret['password'])
    subprocess.run([str(jdk / 'bin/keytool.exe'), '-genkeypair', '-keystore', str(keystore), '-alias', secret['alias'], '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000', '-storepass:env', 'POYANG_KEY_PASSWORD', '-keypass:env', 'POYANG_KEY_PASSWORD', '-dname', 'CN=Poyang Mobile, O=Poyang Ecology, C=CN'], check=True, env=env, capture_output=True)
p = PROJECT / 'export_presets.cfg'
s = p.read_text(encoding='utf-8')
s = s.replace('package/unique_name="com.poyanghu.game"','package/unique_name="com.poyanghu.game.mobile"')
s = s.replace('keystore/release=""', f'keystore/release="{keystore.as_posix()}"')
s = s.replace('keystore/release_user=""', f'keystore/release_user="{secret["alias"]}"')
s = s.replace('keystore/release_password=""', f'keystore/release_password="{secret["password"]}"')
p.write_text(s, encoding='utf-8')
print('Prepared isolated mobile project at', PROJECT)
