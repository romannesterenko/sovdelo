# Патч 32б — изоляция авторизации в тесте обложек

Поверх 32, включает исправление 32а. Только тест: перед API-запросами сбрасываем
закэшированные guards; загрузку отправляем multipart, как существующий helper
WorkspaceTest. Для снятия обложки явно возвращаем web-авторизацию свежего User.
Рабочие маршруты и middleware не меняются.

```bash
cd ~/Projects/sovdelo &&
unzip -o ~/Загрузки/sovdelo-patch-32b-cover-api-test.zip -d . &&
bash test.sh &&
npm run test:frontend &&
npm run build
```

Новая миграция не нужна. Backend-тесты здесь не запускались: PHP отсутствует.
После успеха Git-команды патча 32, добавив patches/README-32a.md и README-32b.md.
