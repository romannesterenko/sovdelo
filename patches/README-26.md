# Патч 26 — метки приложения и этап UX

Поверх 25, остановив flutter run клавишей q. Распаковать в корень.

```bash
python3 clients/flutter-probe/updates/26/apply.py
docker compose -p sovdelo up -d --wait postgres
bash test.sh
cd clients/flutter-probe/app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

После тестов commit/push и зелёный Actions, затем flutter run -d linux / -d 9e4aed70.
PostgreSQL-миграция не нужна, SQLite автоматически обновится v4→v5. Повторный вход
с write-токеном не нужен. В аккаунте: «Метки» создаёт каталог, «Редактировать» выбирает
метки задачи. Они работают офлайн через очередь. Цвет существующей одноимённой метки
на сайте имеет приоритет, новая копия не создаётся.

Git: app/Http/Controllers/Api/SyncController.php app/Http/Controllers/TaskDetailsController.php
 routes/api.php tests/Feature/WorkspaceTest.php clients/flutter-probe docs/client-labels.md
 docs/client-ux-plan.md patches/README-26.md.

UX текущего технического прототипа не окончательный: согласованный следующий этап
переработки зафиксирован в docs/client-ux-plan.md. Следующая функция — вложения.
PHP/Flutter тесты здесь не запускались: SDK нет. Подробности: docs/client-labels.md.
