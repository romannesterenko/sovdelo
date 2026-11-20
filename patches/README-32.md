# Патч 32 — обложки карточек на веб-доске

Поверх установленного сайта с патчем 30. Приостановленный Android-патч 31 не нужен
и в этот архив не включён. Новых composer/npm-зависимостей нет. Нужна миграция БД.

```bash
cd ~/Projects/sovdelo &&
unzip -o ~/Загрузки/sovdelo-patch-32-web-task-covers.zip -d . &&
docker compose -p sovdelo up -d --wait postgres &&
php artisan migrate &&
bash test.sh &&
npm run test:frontend &&
npm run build
```

После успешных проверок:

```bash
cd ~/Projects/sovdelo &&
bash scripts/check-git.sh &&
git add app/Models/Task.php app/Models/TaskAttachment.php app/Services/TaskCovers.php app/Http/Controllers/TaskDetailsController.php app/Http/Controllers/Api/AttachmentsController.php database/migrations/2026_11_20_000018_add_task_covers.php routes/web.php resources/js/App.vue resources/js/TaskExtras.vue resources/js/TaskCover.vue tests/Feature/TaskCoverWorkspaceTest.php docs/task-covers.md patches/README-32.md &&
git commit -m "СовДело: обложки карточек из изображений" &&
git push
```

Дождаться зелёного GitHub Actions; серверная миграция выполняется деплоем.
Обновить страницу сайта. Загрузить изображение через «Файлы», проверить выбор,
снятие обложки и сохранность вложения. Уже загруженные изображения можно назначить
кнопкой «Сделать обложкой» после открытия вкладки.

Здесь прошли build и 14 frontend-тестов; backend-тесты выполнять у пользователя/CI.
Подробности: docs/task-covers.md.
