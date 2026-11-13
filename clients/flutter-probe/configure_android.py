"""Configure the fresh Flutter scaffold; refuse unknown templates before publishing it."""
from pathlib import Path
import re
import sys


def configure(root):
    path = Path(root) / 'android/app/build.gradle.kts'
    source = path.read_text()
    changes = [
        (r'compileSdk\s*=\s*flutter.compileSdkVersion',
         'compileSdk = maxOf(flutter.compileSdkVersion, 35)'),
        (r'minSdk\s*=\s*flutter.minSdkVersion', 'minSdk = 23'),
        (r'compileOptions\s*\{',
         'compileOptions {\n        isCoreLibraryDesugaringEnabled = true'),
    ]
    for pattern, replacement in changes:
        source, count = re.subn(pattern, replacement, source)
        if count != 1:
            raise RuntimeError(f'Неизвестный шаблон Flutter: {pattern}. Файлы приложения не заменены.')
    source += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    path.write_text(source)
    manifest = Path(root) / 'android/app/src/main/AndroidManifest.xml'
    text = manifest.read_text()
    # Secure-storage data must not be restored without the matching Keystore key.
    if '<application' not in text:
        raise RuntimeError('Не найден application в AndroidManifest.xml')
    manifest.write_text(text.replace('<application', '<application android:allowBackup="false"', 1))


if __name__ == '__main__':
    configure(sys.argv[1])
