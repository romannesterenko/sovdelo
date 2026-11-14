# Патч 22 — создание/статусы задач с офлайн-очередью

Поверх 19–21. Изменяет Laravel API и клиент; сначала тесты и выкладка сервера через
GitHub Actions, затем запуск клиента. Новая миграция PostgreSQL не нужна.

```bash
python3 clients/flutter-probe/updates/22/apply.py
docker compose -p sovdelo up -d --wait postgres
bash test.sh
npm run test:frontend
npm run build
cd clients/flutter-probe/app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

Сохранять Git: app/Http/Controllers/Api routes/api.php tests/Feature/WorkspaceTest.php
clients/flutter-probe docs/client-sync.md patches/README-22.md.
После push дождаться зелёного Actions. Запускать flutter run -d linux или -d 9e4aed70.
В экране аккаунта выйти и войти повторно: старый read-токен заменяется на write.
Для офлайн-сценария использовать экран аккаунта, не прежний тестовый список.
Существующие локальные и серверные задачи не удаляются.
Реальные изменения в этом этапе: создать личную задачу без проекта, сменить статус.
После восстановления сети нажать «Синхронизировать».
Полная приёмка и ограничения: docs/client-sync.md.
Тесты PHP/Flutter здесь не выполнялись: соответствующих SDK в среде подготовки нет.
