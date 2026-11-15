# Патч 25 — комментарии Android/Linux

Поверх 24. Остановить flutter run клавишей q, распаковать в корень.
Есть PostgreSQL-миграция: client_uuid комментария для безопасных повторов.
Старые комментарии и задачи сохраняются. SQLite аккаунта обновится v3→v4 автоматически.

```bash
python3 clients/flutter-probe/updates/25/apply.py
docker compose -p sovdelo up -d --wait postgres
php artisan migrate
bash test.sh
cd clients/flutter-probe/app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

После тестов commit/push и дождаться зелёного Actions: новый API и миграция
должны попасть на сервер до запуска клиента. С write-токеном повторный вход не нужен.
Кнопка «Комментарии» — на карточке аккаунта. История кэшируется после открытия.
Набранное сообщение сохраняется только кнопкой «Сохранить и отправить».

Git: app/Http/Controllers/Api/SyncController.php routes/api.php database/migrations
 tests/Feature/WorkspaceTest.php clients/flutter-probe docs/client-comments.md patches/README-25.md.
Подробности: docs/client-comments.md. PHP/Flutter тесты в среде подготовки не выполнялись.
