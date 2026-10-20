"""Prepara una release di Dollarz, oppure ripulisce dopo le build. Non pubblica nulla.

Uso (da dollarz/):
  python tool/release.py 1.0.0            versione nei file, analyze, test, APK, Windows, installer,
                                          SHA256SUMS, controllo di firma e versione
  python tool/release.py 1.0.0 --no-test  come sopra senza analyze e test (già fatti)
  python tool/release.py --clean          ferma Gradle, chiude i java delle build, cancella le cartelle di build

Con la versione già scritta nei file ricompila senza toccarli; con una nuova alza anche il numero di build.
Commit, push e `gh release create` restano a mano: vedi ../doc/rilascio.md.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JDK = r'C:\Users\Luca\dev-tools\jdk17'
ISCC = r'C:\Users\Luca\AppData\Local\Programs\Inno Setup 6\ISCC.exe'
CERT_SHA1 = 'bf083fb551fde690dbfee2353669ede117c9a789'  # firma di Dollarz: l'APK si installa sopra il vecchio
BUILD_DIRS = ['build', 'dist', '.dart_tool', 'android/.gradle', 'android/.kotlin', 'windows/flutter/ephemeral']
ENV = {**os.environ, 'JAVA_HOME': JDK}
FLUTTER = shutil.which('flutter') or r'C:\src\flutter\bin\flutter.bat'


def run(cmd, tail=1):
    """Esegue e mostra solo le ultime righe; se fallisce mostra la coda dell'errore ed esce."""
    print('>', ' '.join(str(c) for c in cmd[:4]), '...' if len(cmd) > 4 else '', flush=True)
    r = subprocess.run([str(c) for c in cmd], cwd=ROOT, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
    out = [x for x in r.stdout.splitlines() if x.strip() and 'MSB8029' not in x]
    if r.returncode != 0:
        print('\n'.join(out[-40:]))
        sys.exit(f'FALLITO ({r.returncode}): {cmd[0]}')
    if tail:
        print('\n'.join('  ' + x for x in out[-tail:]), flush=True)
    return r.stdout


def set_version(version):
    """Scrive la versione in pubspec.yaml e lib/core/ids.dart; ritorna il numero di build."""
    pub = ROOT / 'pubspec.yaml'
    s = pub.read_text(encoding='utf-8')
    m = re.search(r'^version: ([\d.]+)\+(\d+)', s, re.M)
    build = int(m.group(2))
    if m.group(1) == version:
        return build
    build += 1
    pub.write_bytes(pub.read_bytes().replace(m.group(0).encode(), f'version: {version}+{build}'.encode()))
    ids = ROOT / 'lib' / 'core' / 'ids.dart'
    t = ids.read_bytes().decode('utf-8')
    t = re.sub(r"const appVersion = '[^']+';", f"const appVersion = '{version}';", t)
    t = re.sub(r'const appBuild = \d+;', f'const appBuild = {build};', t)
    ids.write_bytes(t.encode('utf-8'))
    print(f'versione {m.group(1)}+{m.group(2)} -> {version}+{build}')
    return build


def sha256(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def prepare(version, test=True):
    if not (ROOT / 'android' / 'key.properties').exists():
        sys.exit('manca android/key.properties (copia da ../keystore/key.properties.backup)')
    build = set_version(version)
    if test:
        run([FLUTTER, 'analyze'])
        run([FLUTTER, 'test'])
    run([FLUTTER, 'build', 'apk', '--release', '--target-platform', 'android-arm,android-arm64'])
    run([FLUTTER, 'build', 'windows', '--release'])
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    apk = dist / f'Dollarz-{version}.apk'
    shutil.copyfile(ROOT / 'build' / 'app' / 'outputs' / 'flutter-apk' / 'app-release.apk', apk)
    run([ISCC, '/Q', f'/DAppVersion={version}', 'installer\\dollarz.iss'], tail=0)
    exe = dist / f'Dollarz-Setup-{version}.exe'
    # l'aggiornamento dentro l'app cerca per nome APK, EXE e SHA256SUMS.txt
    (dist / 'SHA256SUMS.txt').write_text(''.join(f'{sha256(f)} *{f.name}\n' for f in (apk, exe)), newline='\n')

    tools = sorted((Path(os.environ['LOCALAPPDATA']) / 'Android' / 'Sdk' / 'build-tools').iterdir())[-1]
    certs = run([tools / 'apksigner.bat', 'verify', '--print-certs', apk], tail=0).lower()
    badge = run([tools / 'aapt2.exe', 'dump', 'badging', apk], tail=0)
    ok_sign = CERT_SHA1 in certs
    ok_ver = f"versionCode='{build}' versionName='{version}'" in badge
    print(f'\ndist/: {apk.name} ({apk.stat().st_size // 1024} KB), {exe.name} ({exe.stat().st_size // 1024} KB), SHA256SUMS.txt')
    print(f'firma APK {"ok" if ok_sign else "SBAGLIATA"} · versione nell\'APK {"ok" if ok_ver else "SBAGLIATA"} ({version}+{build})')
    if not (ok_sign and ok_ver):
        sys.exit('NON pubblicare')
    print('Poi: commit e push, gh release create (../doc/rilascio.md), python tool/release.py --clean')


def clean():
    gradlew = ROOT / 'android' / 'gradlew.bat'
    if gradlew.exists():
        subprocess.run([str(gradlew), '--stop'], cwd=ROOT / 'android', env=ENV, capture_output=True)
    # i demoni di Gradle e Kotlin restano vivi e tengono parecchi GB di RAM
    ps = ("Get-CimInstance Win32_Process -Filter \"Name='java.exe'\" | Where-Object { $_.CommandLine -match "
          "'GradleDaemon|KotlinCompileDaemon|gradle' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }")
    subprocess.run(['powershell', '-NoProfile', '-Command', ps], capture_output=True)
    for d in BUILD_DIRS:
        shutil.rmtree(ROOT / d, ignore_errors=True)
    (ROOT / '.flutter-plugins-dependencies').unlink(missing_ok=True)  # la riscrive `flutter pub get`
    # i test lasciano cartelle dollarz_* nei temporanei
    tmp = Path(tempfile.gettempdir())
    for d in tmp.glob('dollarz_*'):
        if d.is_dir():
            shutil.rmtree(d, ignore_errors=True)
    left = [d for d in BUILD_DIRS if (ROOT / d).exists()]
    print('pulito' if not left else f'restano: {left}')


if __name__ == '__main__':
    # con l'output rediretto Python usa cp1252 e si ferma sul "√" di flutter build
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if '--clean' in sys.argv:
        clean()
    elif len(args) == 1 and re.fullmatch(r'\d+\.\d+\.\d+', args[0]):
        prepare(args[0], test='--no-test' not in sys.argv)
    else:
        sys.exit(__doc__)
