# Патч 24 — чек-листы Android/Linux с офлайн-очередью

Поверх 23, остановив flutter run клавишей q. Распаковать в корень, затем:

```bash
python3 clients/flutter-probe/updates/24/apply.py
docker compose -p sovdelo up -d --wait postgres
bash test.sh
cd clients/flutter-probe/app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

Git: app/Http/Controllers/Api/SyncController.php tests/Feature/WorkspaceTest.php
clients/flutter-probe docs/client-checklists.md patches/README-24.md.
После commit/push дождаться зелёного Actions, затем запускать Linux/Android.
Новый API нужен для записи чек-листов. Повторный вход с write-токеном не требуется.
SQLite обновится автоматически, прежние очереди сохранятся. Серверная миграция не нужна.
Редактирование — в экране аккаунта, а не в прежнем тестовом локальном списке.
Подробности: docs/client-checklists.md. PHP/Flutter тесты здесь не запускались — SDK нет.
