# Патч 33 — компактная доска и сохранение фильтров

Поверх 32/32а/32б. Только веб-интерфейс и frontend-тесты, миграций нет.

```bash
cd ~/Projects/sovdelo &&
unzip -o ~/Загрузки/sovdelo-patch-33-web-board-layout.zip -d . &&
npm run test:frontend &&
npm run build &&
bash scripts/check-git.sh &&
git add resources/js/App.vue resources/js/TaskCover.vue resources/js/boardPreferences.ts resources/css/app.css scripts/test-frontend.mjs tests/Frontend/board-preferences.test.mjs tests/Frontend/cover-style.test.mjs docs/web-board-preferences.md patches/README-33.md &&
git commit -m "СовДело: компактная доска и сохранение фильтров" &&
git push
```

После зелёного GitHub Actions обновить сайт Ctrl+Shift+R. Проверить перенос,
обложки и сохранение выбранных фильтров после обновления страницы.

Состояние фильтров хранится в браузере с отдельным ключом аккаунта. Вид «Доска»
открывается при входе/обновлении, включая ранее выбранный рабочий раздел.
Подробности и приёмка: docs/web-board-preferences.md.
