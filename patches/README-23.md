# Патч 23 — редактор задачи и офлайн-проекты

Устанавливать поверх 22, остановив flutter run клавишей q.
Изменяет Laravel SyncController/тесты и Flutter-клиент. Новая PostgreSQL-миграция
не нужна. SQLite аккаунта обновится автоматически, файлы базы не удалять.

```bash
python3 clients/flutter-probe/updates/23/apply.py
docker compose -p sovdelo up -d --wait postgres
bash test.sh
cd clients/flutter-probe/app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

После тестов commit/push, дождаться зелёного Actions, затем flutter run -d linux
или flutter run -d 9e4aed70. Выход/повторный вход не нужен при write-токене патча 22.
Редактор открывается кнопкой «Редактировать» в карточке аккаунта.
Git: app/Http/Controllers/Api/SyncController.php tests/Feature/WorkspaceTest.php
clients/flutter-probe docs/client-task-editor.md patches/README-23.md.
Подробности и приёмка: docs/client-task-editor.md.
PHP/Flutter тесты здесь не запускались: SDK отсутствуют в среде подготовки.
