# Патч 17 — ежедневные копии и автоматическое скачивание на Ubuntu

Требует работающий патч 16 (maintenance guard в Nginx). СовДело на 31.31.207.196; копии читаются отдельным ключом только через rrsync -ro. Ключи СовПути и ключ деплоя не изменяются.

## 1. Локально: распаковать и создать отдельный read-only ключ

```bash
cd ~/Projects/sovdelo &&
unzip -o ~/Загрузки/sovdelo-patch-17-local-backups.zip -d . &&
python3 -m unittest discover -s deploy/tests -p 'test_*.py' &&
install -d -m 0700 ~/.ssh &&
{ if [ ! -f ~/.ssh/sovdelo_backup ]; then ssh-keygen -t ed25519 -f ~/.ssh/sovdelo_backup -N '' -C sovdelo-backup; fi; } &&
cat ~/.ssh/sovdelo_backup.pub
```

Скопировать публичную строку. Закрытый ключ остаётся в ~/.ssh/sovdelo_backup на компьютере, в репозиторий/чат/GitHub он не добавляется.

```bash
scp -o PubkeyAuthentication=no -o PreferredAuthentications=password \
 ~/Загрузки/sovdelo-patch-17-local-backups.zip \
 root@31.31.207.196:/root/sovdelo-patch-17-local-backups.zip
```

## 2. Сервер root

```bash
mkdir -p /root/sovdelo-backup-installer &&
python3 -m zipfile -e /root/sovdelo-patch-17-local-backups.zip /root/sovdelo-backup-installer &&
bash /root/sovdelo-backup-installer/deploy/server/setup-backups.sh
```

На запрос вставить ключ из sovdelo_backup.pub. Установщик:
- добавляет отдельную строку restrict + /usr/bin/rrsync -ro /var/backups/sovdelo в authorized_keys;
- устанавливает root-owned скрипты и sovdelo-backup.service/timer;
- создаёт первую согласованную копию и пробно восстанавливает базу в отдельную временную БД;
- после успешного восстановления включает ежедневный таймер на 03:20 Europe/Moscow. Persistent=true позволяет выполнить пропущенное после запуска сервера.

При копировании СовДело кратко переводится в обслуживание через свой Nginx-маркер. Останавливаются только собственные очередь/планировщик; свои FPM-запросы завершаются. Копия содержит PostgreSQL database.dump, storage/app в files.tar.gz (включая приватные вложения), .env с ключом приложения, метаданные релиза и SHA256SUMS. По завершении, в том числе при ошибке копирования, прежние службы и доступность сайта восстанавливаются: схема/данные при резервном копировании не изменяются.

Общий lock предотвращает одновременный backup/deploy. Если идёт деплой, самостоятельное копирование завершится с сообщением о занятости; деплой уже делает свою копию. Если maintenance-маркер остался от ошибки предыдущего деплоя, резервный скрипт не снимает его самовольно.

Пробный restore использует отдельную временную роль без прав суперпользователя и новую БД sovdelo_restore_check_<дата>_<pid> и pg_restore --single-transaction. В ней проверяются таблицы users/tasks; затем удаляются только созданные проверочные БД и роль. Производственная БД не восстанавливается и не очищается. До restore проверяются суммы и безопасная структура архива файлов; файлы проверяются чтением архива, не заменяют живые вложения. Успех: RESTORE VERIFIED и количество пользователей/задач. Полный запуск отдельного Laravel из восстановленной копии в этот тест не входит.

## 3. Снова локально, от roman

```bash
cd ~/Projects/sovdelo &&
bash deploy/local/install-backups.sh
```

Первая загрузка выполняется сразу и проверяется. Затем включается пользовательский systemd-таймер: через 2 минуты после старта user manager и каждый час, с догоняющим запуском после пропуска. Таймер работает в пользовательской сессии Ubuntu; выключенный компьютер копии не скачивает.

Копии: ~/Backups/sovdelo. Закрытая папка 0700, файлы 0600 — в них есть .env и ключ приложения. Передача использует ~/.ssh/sovdelo_backup, BatchMode, IdentitiesOnly и строгую проверку host key по уже существующему ~/.ssh/known_hosts. IP уже использовался для SCP; если хост неизвестен на новом компьютере, сначала проверить его ключ по доверенному серверному терминалу, не отключать проверку.

Используется только чтение удалённого каталога. Нет --delete: локальные копии сохраняются, даже если удалены на сервере. После передачи сверяются SHA-256 трёх обязательных файлов и пути/типы в файловом архиве. Папка без готового манифеста считается неполной. Несовпадение суммы/отсутствующий файл дают ошибку, данные не объявляются проверенными. Неизменившиеся уже проверенные снимки берутся из локального кэша по размеру/mtime/содержимому манифеста, не перечитываются гигабайты каждый час. Серверный кэш проверки не скачивается.

## 4. Сохранить в Git и отправить обычным Actions-деплоем

```bash
cd ~/Projects/sovdelo &&
bash scripts/check-git.sh &&
git add .github/workflows/checks.yml deploy patches &&
{ if ! git diff --cached --quiet; then git commit -m "СовДело: ежедневные копии и скачивание на Ubuntu"; fi; } &&
git push
```

Обработчики root установлены шагом 2; pipeline выкладывает исходники, но не меняет доверенные root-скрипты из архива автоматически.

## Проверки и управление

Локально:

```bash
systemctl --user list-timers sovdelo-backup-pull.timer --no-pager
journalctl --user -u sovdelo-backup-pull.service -n 40 --no-pager
systemctl --user start sovdelo-backup-pull.service
```

Ручная полная перепроверка всех локальных снимков (без кэша):

```bash
python3 ~/.local/lib/sovdelo-backup/verify-backups.py ~/Backups/sovdelo --force
```

Сервер:

```bash
systemctl list-timers sovdelo-backup.timer --no-pager
journalctl -u sovdelo-backup.service -n 40 --no-pager
systemctl start sovdelo-backup.service
bash /usr/local/lib/sovdelo/verify-restore.sh
```

Копии перед деплоем из патча 16 тоже скачиваются и проверяются. Автоочистка копий/релизов пока не включена; перед каждой новой копией проверяется свободное место. Диагностика скачивания — .last-sync.json в локальной папке и журнал user service. Отчёты содержат имена/количества/статус, не пароли и не содержимое .env. Присылать в чат только отчёты, не сами конфигурации/архивы с секретами.

## Проверено при подготовке

20 тестов Python (7 новых), синтаксис server/local shell-скриптов. Новые проверки: контрольные суммы и кэш; изменение данных; неполный снимок; небезопасный манифест; выход за каталог в tar; symlink; отсутствующий файл. Здесь нет доступа к production/PostgreSQL/пользовательскому systemd: фактический restore и SSH-скачивание подтверждаются выводом установки. В приложении Laravel/Vue изменений нет.
