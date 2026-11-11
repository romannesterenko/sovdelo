# Исправление 08a: frontend-тесты без встроенной поддержки TypeScript в Node

В сборке Node.js пользователя v22.22.1 встроенная обработка TypeScript отсутствует (ERR_NO_TYPESCRIPT). Исправление использует уже установленный пакет typescript для преобразования planning.ts во временный JS-модуль, затем запускает обычный node --test. Дополнительные зависимости и смена Node не нужны. Временная папка удаляется после тестов. Vue/TypeScript production build продолжает выполнять полную проверку типов через vue-tsc.

Применить поверх патча 08:

```bash
cd ~/Projects/sovdelo
unzip -o ~/Загрузки/sovdelo-patch-08a-frontend-tests.zip -d .
npm run test:frontend
npm run build
```

Миграции и повторное применение 08 не требуются. Все 34 Laravel-теста уже прошли у пользователя (154 assertions). Цепочка предыдущей команды остановилась до сборки и Git, поэтому сохраните весь патч 08 вместе с исправлением:

```bash
git add app routes database resources tests patches package.json scripts/check.sh scripts/test-frontend.mjs .github/workflows/checks.yml
bash scripts/check-git.sh && git commit -m "СовДело: планирование и совместимый запуск frontend-тестов"
git push
```

Проверено: 8 тестов новым запуском, 8 тестов с NODE_OPTIONS=--no-experimental-strip-types и production build. Содержимое planning.ts и сами сценарии тестов не изменялись; изменён только способ загрузки TypeScript-модуля.
