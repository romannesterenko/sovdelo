"""Update only unmodified probe sources; never touch SQLite or secure storage."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile


def apply(root):
    root = Path(root)
    app = root / 'app'
    if not app.is_dir():
        raise SystemExit('Сначала создайте приложение: bash clients/flutter-probe/bootstrap.sh')
    template = root / 'template'
    previous = json.loads((root / 'updates/22/previous-files.json').read_text())
    files = [*previous, 'lib/account_store.dart', 'lib/account_sync.dart', 'test/account_sync_test.dart']
    changes = []
    # Preflight every file before changing any file.
    for name in files:
        source, target = template / name, app / name
        new_bytes = source.read_bytes()
        if target.exists():
            current = target.read_bytes()
            if current == new_bytes:
                continue
            if hashlib.sha256(current).hexdigest() != previous.get(name):
                raise SystemExit(f'Файл изменён вручную: {target}. Обновление остановлено без перезаписи.')
        elif name in previous:
            raise SystemExit(f'Не найден ожидаемый файл: {target}. Обновление остановлено.')
        changes.append((target, new_bytes))
    if not changes:
        print('Этап 22 уже установлен.')
        return
    # Keep a source backup outside the repository and outside the app database.
    backup_root = Path.home() / 'Backups/sovdelo-client-source'
    backup_root.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix='before-22-', dir=backup_root))
    for target, content in changes:
        if target.exists():
            saved = backup / target.relative_to(app)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, saved)
    for target, content in changes:
        target.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix='.update-', dir=target.parent)
        try:
            with os.fdopen(fd, 'wb') as output:
                output.write(content)
            os.chmod(temporary, 0o644)
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    print(f'Этап 22 установлен. Копия прежних исходников: {backup}')


if __name__ == '__main__':
    apply(Path(__file__).resolve().parents[2])
