# Патч 29а — корректное завершение WorkspaceWorker

Поверх патча 29. Исправляет must_call_super: dispose напрямую вызывает
super.dispose один раз; close ждёт завершения запроса и закрытия SQLite.
Новые запросы и уведомления при закрытии запрещены. Данные не меняются.

Полностью остановить приложение, распаковать в корень проекта, выполнить:

```bash
python3 clients/flutter-probe/updates/29a/apply.py
cd clients/flutter-probe/app
flutter analyze --no-fatal-infos
flutter test
flutter run -d linux
```

Установщик проверен на исходниках 29, повторном запуске и отказе при ручных
изменениях. Flutter SDK в среде подготовки отсутствует; analyze/test здесь не запускались.
