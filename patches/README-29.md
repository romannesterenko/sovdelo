# Патч 29 — неблокирующая синхронизация и защита черновика

Поверх 28. Полностью остановить flutter run клавишей q, распаковать в корень.

```bash
python3 clients/flutter-probe/updates/29/apply.py
cd clients/flutter-probe/app
flutter analyze --no-fatal-infos
flutter test
flutter run -d linux
```

Новых пакетов, API и миграций нет. Очередь и токен сохраняются. Патч требует полного
перезапуска, чтобы прежние экземпляры worker/экрана были уничтожены.
Фоновая работа — внутри открытого приложения, не отдельный Android OS service.
Обычные изменения не ждут HTTP; выход/явное скачивание могут ждать текущий запрос.
Документация и приёмка: docs/client-async-sync.md.
Git: clients/flutter-probe docs/client-async-sync.md patches/README-29.md.
Flutter SDK здесь отсутствует: analyze/test и проверка устройств выполняются локально.
