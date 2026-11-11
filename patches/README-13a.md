# Патч 13a — точные байты JSON при импорте

Применять поверх 13. Laravel TrimStrings обрезал внешние пробелы поля payload до контроллера. Из-за этого файл с добавленным завершающим пробелом получал прежнее содержимое, и тест проверки fingerprint возвращал 200 вместо 422.

Поле payload исключено из TrimStrings. Остальные поля обрабатываются как раньше. Существующий тест test_transfer_copy_retry_is_idempotent_and_changed_file_requires_preview проверяет оба случая: старый fingerprint для изменённого файла и повтор использованного ключа с другим fingerprint. Проверки не ослаблены.

Миграций в этом исправлении нет. Данные не изменяются. Здесь PHP/Docker недоступны — backend-тесты необходимо повторить на Ubuntu.

```bash
cd ~/Projects/sovdelo &&
unzip -o ~/Загрузки/sovdelo-patch-13a-import-payload.zip -d . &&
bash test.sh &&
npm run test:frontend &&
npm run build &&
git add app bootstrap routes database resources tests patches &&
bash scripts/check-git.sh &&
git commit -m "СовДело: импорт и экспорт с точной проверкой JSON" &&
git push
```

Команды Git включают все изменения патча 13: предыдущий блок остановился на тестах до сборки/коммита. Если dev-процесс использует долгоживущий Laravel worker, перезапустить его после изменения bootstrap; обычный artisan serve подхватит код при следующем запросе.
