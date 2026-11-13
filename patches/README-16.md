# Патч 16 — автоматическое развёртывание из GitHub Actions

Сервер 31.31.207.196, сайт совдело.рф, репозиторий romannesterenko/sovdelo. Применять после успешного запуска 15/15a. Приватный ключ старого rrsync не используется и его настройки не меняются.

## 1. Локально: распаковать и создать отдельный ключ

```bash
cd ~/Projects/sovdelo &&
unzip -o ~/Загрузки/sovdelo-patch-16-github-actions.zip -d . &&
python3 -m unittest discover -s deploy/tests -p 'test_*.py' &&
install -d -m 0700 ~/.ssh &&
{ if [ ! -f ~/.ssh/sovdelo_actions ]; then ssh-keygen -t ed25519 -f ~/.ssh/sovdelo_actions -N '' -C sovdelo-actions; fi; } &&
cat ~/.ssh/sovdelo_actions.pub
```

Скопировать напечатанную строку ОТКРЫТОГО ключа. Приватный ключ остаётся на компьютере, потом переносится напрямую в GitHub Secret — в чат его не отправлять.

Передать ZIP установщика на сервер, используя пароль (ограниченные rrsync-ключи для этой первоначальной установки не подходят):

```bash
scp -o PubkeyAuthentication=no -o PreferredAuthentications=password \
  ~/Загрузки/sovdelo-patch-16-github-actions.zip \
  root@31.31.207.196:/root/sovdelo-patch-16-github-actions.zip
```

## 2. На сервере root

```bash
mkdir -p /root/sovdelo-actions-installer &&
python3 -m zipfile -e /root/sovdelo-patch-16-github-actions.zip /root/sovdelo-actions-installer &&
bash /root/sovdelo-actions-installer/deploy/server/setup-actions.sh
```

На запрос вставить строку из sovdelo_actions.pub и нажать Enter. Установщик добавит ключ с restrict и принудительной командой, принимающей только протокол `deploy <40-значный SHA> <номер Actions run>`. Shell, SCP/SFTP, forwarding и произвольные команды этим ключом не разрешаются. Архив передаётся в stdin разрешённой SSH-команды; rrsync не требуется. Максимум архива 64 МиБ, приём ограничен 180 секундами.

Появится строка для SOVDELO_KNOWN_HOSTS из реального серверного публичного Ed25519 host key. Скопировать её целиком. Существующий совпавший ключ с другим ограничением не изменяется: нужен отдельный ключ.

Корневые обработчики устанавливаются в /usr/local/lib/sovdelo, принадлежат root и не обновляются содержимым очередного релиза. Конфигурация только СовДела получает maintenance-маркер /var/www/sovdelo/deploying и отдельный health-путь /up. Nginx проверяется перед reload, конфигурации СовПути не редактируются.

## 3. GitHub Secrets

Открыть https://github.com/romannesterenko/sovdelo/settings/secrets/actions

Добавить Repository secrets:

| Имя | Значение |
| --- | --- |
| SOVDELO_HOST | 31.31.207.196 |
| SOVDELO_SSH_KEY | Всё содержимое локального ~/.ssh/sovdelo_actions, включая BEGIN/END и переводы строк; это НЕ .pub |
| SOVDELO_KNOWN_HOSTS | Строка, напечатанная серверным setup-actions.sh |

Ключ можно открыть локальным текстовым редактором и скопировать непосредственно в GitHub. Приватный ключ в проект, ZIP, git или чат не добавлять. Порт SSH — 22, пользователь root, ключ ограничен серверным протоколом СовДела.

## 4. Коммит и первый push — после настройки Secrets

```bash
cd ~/Projects/sovdelo &&
bash scripts/check-git.sh &&
git add .github/workflows/checks.yml deploy patches &&
{ if ! git diff --cached --quiet; then git commit -m "СовДело: автоматический деплой через GitHub Actions"; fi; } &&
git push
```

Открыть https://github.com/romannesterenko/sovdelo/actions . Workflow «SovDelo checks and deploy» проверяет PHP 8.3 + PostgreSQL 16, 89 WorkspaceTest, 14 frontend-тестов и Vue/TypeScript; также shell-синтаксис и 13 тестов скриптов деплоя. Только push в main после успешных проверок выполняет упаковку и отправку. PR и другие ветки не деплоятся. workflow_dispatch оставлен для проверок; повторный деплой запускается через Re-run соответствующего push-run, с тем же номером и SHA.

GitHub собирает один раз: build-artifact.py берёт исходники из Git HEAD и добавляет уже проверенный public/build. .env, storage runtime, vendor, node_modules и локальные данные не передаются. На сервере PHP-зависимости устанавливаются composer install по lock от имени sovdelo, не root.

Деплои одной ветки последовательны; сервер также использует flock. Старый номер run после более нового успешного отклоняется. Изменять имя/пересоздавать workflow с новым счётчиком следует осознанно: номер защищает от случайного повторного выката старой версии.

## Обновление на сервере

1. Проверка архива/SHA/номера запуска, распаковка нового релиза, composer install до остановки сайта.
2. Проверка места под копию. Nginx блокирует новые запросы приложения, останавливаются только очередь и планировщик СовДела; собственные FPM-процессы совдело завершают активные запросы. Общий FPM и СовПуть не перезапускаются.
3. В /var/backups/sovdelo/<дата-run> создаются database.dump, files.tar.gz (storage/app), .env, путь прошлого релиза и SHA256SUMS. Каталог root-only, секреты не выводятся. pg_restore --list проверяет читаемость каталога дампа, но не заменяет восстановление.
4. migrate --force без сброса данных, config:cache/view:cache, права, переключение current, health HTTPS /up и проверка подключения через migrate:status.
5. Запуск очереди/планировщика, запись последнего успешного SHA и открытие сайта.

При ошибке до maintenance работающий релиз остаётся доступным. При ошибке после остановки записи maintenance остаётся включённым и workflow красный. Бэкап и старый релиз сохраняются, автоматического отката БД нет. Удалять maintenance-маркер или восстанавливать базу вслепую не нужно — сначала проверить вывод и журнал. Полный restore drill, автоматические ежедневные и внешние резервные копии — следующие задачи SD-005; копия на том же VPS их не заменяет. Старые копии/релизы автоматически не удаляются, место нужно контролировать.

Проверить после первого зелёного run: главная СовДела, вход, существующие задачи/файлы, таймер/напоминания; затем главная СовПути. В логах Actions должны быть DEPLOYED <SHA> и BACKUP <каталог>.

## Проверки подготовки

13 тестов Python и bash -n прошли, YAML разбирается. Новый серверный обработчик и GitHub Secrets из этой среды не установлены; реальное выполнение проверяется первым workflow. Код Laravel/Vue в этом патче не менялся. Файлы setup-actions/ssh-deploy/update-release/receive-release/validate-release устанавливаются root только отдельной административной установкой; будущий deploy не исполняет серверные скрипты из загруженного архива от root.
