# Патч 30 — доступ помощника, ответственность и перенос плана

Поверх 29/29а. Flutter-файлы не изменяются. Миграция добавляет четыре таблицы,
не меняет существующие задачи. План переносится отдельно по кнопке с предпросмотром.

```bash
cd ~/Projects/sovdelo
unzip -o ~/Загрузки/sovdelo-patch-30-project-agents.zip -d .
docker compose -p sovdelo up -d --wait postgres
php artisan migrate
bash test.sh
python3 integrations/mcp/test_bridge.py
npm run test:frontend
npm run build
```

Выполнять последовательно, при ошибке остановиться. После успешных проверок:

```bash
bash scripts/check-git.sh
git add app/Models/ProjectAgent.php app/Services/ProjectAgents.php app/Services/DevelopmentPlan.php app/Services/ApiDevices.php app/Http/Middleware/AgentAccess.php app/Http/Controllers/AgentWorkspaceController.php app/Http/Controllers/AgentMcpController.php app/Http/Controllers/DevelopmentPlanController.php routes/api.php routes/web.php database/migrations/2026_11_16_000017_create_project_agents.php resources/js/AccountSettings.vue resources/js/ProjectControl.vue resources/plans resources/integrations tests/Feature/ProjectAgentsTest.php integrations docs/project-agents.md docs/api-v1.md patches/README-30.md
git commit -m "СовДело: проектный помощник, приёмка задач и перенос плана"
git push
```

Дождаться зелёного Actions. На сайте: Профиль → Проекты и помощники → Перенести
план СовДела → проверить предпросмотр → Перенести. Затем выдать доступ выбранному
проекту и запустить локальный --setup, как в docs/project-agents.md.

Патч не подключает браузерный чат автоматически и не запускает фонового агента.
MCP endpoint готов для bearer-авторизации; OAuth/установка собственного плагина
остаются отдельной настройкой клиента. Не отправлять токен в переписку.
