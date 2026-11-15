# Патч 28 — рабочий интерфейс приложения, этап UX 1

Поверх 27. Полностью остановить flutter run клавишей q, распаковать в корень.

```bash
python3 clients/flutter-probe/updates/28/apply.py
cd clients/flutter-probe/app
flutter analyze --no-fatal-infos
flutter test
flutter run -d linux
```

Новых пакетов, серверных маршрутов и миграций нет. Перезапуск нужен для нового home.
Тестовый экран перенесён в настройки, данные и токен не удаляются.
Изменения: навигация, компактный список, поиск/фильтры, быстрая задача с проектом,
локальная деталка и полноэкранные мобильные редактор/комментарии/файлы.
Это первый этап UX; блокирующее ожидание сети и доска остаются следующим шагом.

Git: clients/flutter-probe docs/client-ux-stage-1.md patches/README-28.md.
После проверки Linux повторить flutter run -d 9e4aed70 на телефоне.
Flutter SDK здесь нет: analyze/test/layout должны быть проверены на машине разработчика.
Подробности: docs/client-ux-stage-1.md.
