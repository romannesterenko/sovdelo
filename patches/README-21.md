# Патч 21 — аккаунт и просмотр данных с сайта

Поверх патчей 19, 19a и 20. Остановить flutter run клавишей q, распаковать в корень.

```bash
python3 clients/flutter-probe/updates/21/apply.py
cd clients/flutter-probe/app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run -d linux
```

Кнопка «Открыть аккаунт СовДела» открывает вход и списки сайта. Токен только read.
Локальные задачи не отправляются, серверные пока доступны только онлайн.
Инструкция проверки: docs/client-account.md. Тесты Flutter здесь не запускались
из-за отсутствия SDK. Обновляющий скрипт проверяет исходники и сохраняет резервную
копию в ~/Backups/sovdelo-client-source; не меняет SQLite, пароль или токены.
Git: clients/flutter-probe docs/client-account.md patches/README-21.md.
