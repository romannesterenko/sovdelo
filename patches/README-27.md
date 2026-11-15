# Патч 27 — вложения приложения

Поверх 26. Полностью остановить flutter run клавишей q. После распаковки:

```bash
python3 clients/flutter-probe/updates/27/apply.py
docker compose -p sovdelo up -d --wait postgres
php artisan migrate
bash test.sh
cd clients/flutter-probe/app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

Новая PostgreSQL-миграция добавляет идентичность вложения; SQLite автоматически v5→v6.
Добавлен native FilePicker: требуется полный перезапуск, hot reload недостаточен.
После тестов commit/push и зелёный Actions с серверной миграцией, затем запуск клиента.
Write-токен прежний. На карточке аккаунта: «Файлы», «Добавить файл», «Сохранить как…».
Лимиты сайта сохраняются: 10МиБ/файл, 50/задачу, 250МиБ/аккаунт. Подробности и приёмка:
docs/client-attachments.md. Тесты PHP/Flutter здесь не запускались: SDK отсутствуют.
Следом — этап удобства интерфейса docs/client-ux-plan.md.
