"""Verify and publish the local APK without shipping signing credentials."""
from pathlib import Path, PurePosixPath
import hashlib, json, os, shutil, struct, subprocess, zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/android'
DELIVERY = ROOT / 'build/android/delivery-0.2.11'
DELIVERY.mkdir(parents=True, exist_ok=True)
source = BUILD / '鄱阳归翎-手机版-0.2.11.apk'
apk = DELIVERY / 'poyang-mobile-0.2.11.apk'
shutil.copy2(source, apk)
jdk = Path('C:/android/jdk17/jdk-17.0.20.1+1')
sdk = Path('C:/android/sdk/build-tools/34.0.0')
signature = subprocess.run([str(jdk / 'bin/java.exe'), '-jar', str(sdk / 'lib/apksigner.jar'), 'verify', '--verbose', '--print-certs', str(apk)], capture_output=True, text=True, encoding='utf-8', check=True).stdout
manifest = subprocess.run([str(sdk / 'aapt.exe'), 'dump', 'badging', apk.name], cwd=DELIVERY, capture_output=True, text=True, encoding='utf-8', errors='replace', check=True).stdout
alignment = subprocess.run([str(sdk / 'zipalign.exe'), '-c', '4', str(apk)], capture_output=True, text=True, check=True)
assert "name='com.poyanghu.game.mobile'" in manifest
assert "versionName='0.2.11-mobile'" in manifest
assert "versionCode='212'" in manifest
assert "'arm64-v8a'" in manifest and "'armeabi-v7a'" in manifest
assert 'application-debuggable' not in manifest
assert 'android.permission.CAMERA' not in manifest and 'android.permission.RECORD_AUDIO' not in manifest and 'android.permission.ACCESS_FINE_LOCATION' not in manifest
native_alignment = {}
with zipfile.ZipFile(apk) as archive:
    names = archive.namelist()
    assert not any(any(x in n for x in ['signing-local', 'keystore', 'export_presets', 'tests/', 'tools/', 'addons/']) for n in names)
    assert 'assets/project.binary' in names
    assert any('mobile_port' in n for n in names)
    for name in names:
        if name.startswith('lib/arm64-v8a/'):
            data = archive.read(name)
            phoff = struct.unpack_from('<Q', data, 32)[0]
            entry_size, count = struct.unpack_from('<HH', data, 54)
            aligns = [struct.unpack_from('<Q', data, phoff + i * entry_size + 48)[0]
                      for i in range(count) if struct.unpack_from('<I', data, phoff + i * entry_size)[0] == 1]
            assert aligns and all(x >= 16384 for x in aligns)
            native_alignment[name] = aligns
    # Extract the exact shipped Godot assets for a final desktop launch check.
    extracted = BUILD / 'apk-assets'
    extracted.mkdir(exist_ok=True)
    for info in archive.infolist():
        if not info.filename.startswith('assets/') or info.is_dir():
            continue
        rel = PurePosixPath(info.filename).relative_to('assets')
        assert '..' not in rel.parts
        target = extracted.joinpath(*rel.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read(info))
report = {'file': apk.name, 'bytes': apk.stat().st_size,
          'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
          'manifest': [line for line in manifest.splitlines() if line.startswith(('package:', 'sdkVersion:', 'targetSdkVersion:', 'native-code:', 'uses-permission:', 'uses-feature:'))],
          'signature': signature.splitlines(), 'arm64_elf_load_alignment': native_alignment,
          'private_or_test_files': False, 'zip_alignment': 'passed',
          'test_logs': ['ending-victory-mobile.log', 'ending-victory-desktop.log', 'input-window-0211.log', 'volume-0211.log'],
          'real_android_device_tested': False}
(DELIVERY / 'apk-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
shutil.copy2(ROOT / 'docs/ANDROID_PORT.md', DELIVERY / '手机版说明.md')
print(json.dumps({k: report[k] for k in ['file','bytes','sha256','manifest','zip_alignment']}, ensure_ascii=False, indent=2))
print('APK_SIGNATURE_AND_CONTENTS_VERIFIED')
