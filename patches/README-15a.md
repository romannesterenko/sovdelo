# 15a — исключение временных файлов тестов

Упаковку релиза блокировал неотслеживаемый storage/framework/testing/. Скрипт apply-15a-ignore-testing.py добавляет только эту папку в .gitignore, сохраняет пользовательские правила и не удаляет файлы. Повторное применение безопасно. Проверка остальных неотслеживаемых файлов при упаковке сохранена.

Запустить локально после распаковки:

```bash
cd ~/Projects/sovdelo &&
python3 patches/apply-15a-ignore-testing.py &&
git add .gitignore deploy patches &&
{ if ! git diff --cached --quiet; then git commit -m "СовДело: исключить временные файлы тестов из релиза"; fi; } &&
git push &&
bash deploy/package.sh ~/Загрузки/sovdelo-release.tar.gz &&
scp ~/Загрузки/sovdelo-release.tar.gz root@xn--b1aedylep.xn--p1ai:/root/sovdelo-release.tar.gz
```

Если коммит уже сделан, условие пропустит его и продолжит push/упаковку. Не добавлять storage/framework/testing в индекс. Архив релиза по-прежнему формируется только из Git HEAD и заново собранного фронтенда.
