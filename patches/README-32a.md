# Патч 32а — исправление теста токена обложек

Поверх 32. В fixture TaskCoverWorkspaceTest перечитываем User после создания:
значение auth_version по умолчанию заполняет PostgreSQL, свежая Eloquent-модель
до refresh ещё не содержит его. Рабочие маршруты и данные не меняются.

```bash
cd ~/Projects/sovdelo &&
unzip -o ~/Загрузки/sovdelo-patch-32a-cover-test.zip -d . &&
bash test.sh &&
npm run test:frontend &&
npm run build
```

После успеха выполнить Git-команды патча 32, добавив patches/README-32a.md.
Повторная миграция не нужна. Backend-тесты здесь не запускались: PHP отсутствует.
