# Патч 20 — локальная модель задач и очередь изменений

Установить поверх 19 + 19a. Завершить flutter run клавишей q на обеих платформах.
Распаковать ZIP в корень репозитория, затем:

```bash
python3 clients/flutter-probe/updates/20/apply.py
cd clients/flutter-probe/app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run -d linux
```

Обновляющий скрипт проверяет прежние исходники до перезаписи и делает их резервную
копию вне репозитория. При собственных правках приложение не перезаписывает.
База обновляется автоматически при запуске, существующие задачи сохраняются.
Тот же app/ запускается на Android: `flutter run -d 9e4aed70`.

Сохранять в Git: clients/flutter-probe, docs/offline-client.md, patches/README-20.md.
Серверный код не меняется. Не выполнять php artisan migrate для этой SQLite-миграции.
Запуск/тесты Flutter выполняются на компьютере разработчика: SDK здесь отсутствует.
Авторизация и обмен с сервером остаются следующим этапом.
