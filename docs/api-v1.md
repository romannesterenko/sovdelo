# API v1 СовДела

Базовый адрес: https://совдело.рф/api/v1 (в клиентах можно использовать xn--b1aedylep.xn--p1ai). JSON, UTF-8, HTTPS. Для всех маршрутов кроме входа: `Authorization: Bearer <token>`, `Accept: application/json`. API принимает только Bearer-токены устройств, cookie веб-сайта недостаточно. Существующий веб-интерфейс продолжает использовать прежние маршруты; миграция фронтенда на API не входит в этот этап.

## Вход и устройства

`POST /auth/token`: email, password, device_name (до 80 символов), access (`read` либо `write`). 201: data.token, token_type=Bearer, expires_at, access. Токен показывается только при выдаче, действует 30 дней, сервер хранит SHA-256. Не более 20 активных токенов текущей версии пароля. После срока требуется новый вход с паролем, refresh token пока не предусмотрен. Вход ограничен 6 попытками в минуту на IP+email и 20 на IP.

`GET /me`: id, name, email, timezone, theme.
`GET /auth/devices`: до 100 последних записей устройств без секретов; valid учитывает срок и смену пароля.
`DELETE /auth/token`: отзыв текущего токена, доступен и read-токену.
`DELETE /auth/devices/{id}`: токен write и JSON current_password; только устройство текущего владельца.

Из веб-профиля подключённые приложения видны отдельным разделом и отзываются после проверки текущего пароля. Смена пароля меняет auth_version: все прежние API-токены отклоняются. Отзыв веб-сессии и отзыв API-устройства — разные действия.

Токены этого этапа относятся к собственному аккаунту и его личным проектам. Служебные учётные записи, проектные токены агента, роли и MCP остаются SD-038–043, в этом этапе не реализуются.

## Ответы и ошибки

Успех: `{"data": ..., "meta":{"api_version":"1"}}`.
Ошибка: `{"error":{"code":"validation_failed","message":"...","details":{"title":["..."]}},"meta":{"api_version":"1"}}`.

401 unauthenticated; 403 forbidden; 404 not_found (чужие объекты тоже 404); 409 conflict; 413 payload_too_large; 422 validation_failed; 429 rate_limited. Для непредвиденных ошибок — 500 server_error без stack trace/текста SQL. HTTP Retry-After сохраняется для ограничения частоты. API — до 120 запросов в минуту на аккаунт. Тело защищённых запросов — до 128 КиБ.

Списки: page>=1, per_page=1..100 (по умолчанию 25), meta содержит page, per_page, total, last_page. Даты плана/дедлайна — YYYY-MM-DD, моменты времени — ISO 8601.

## Проекты

- `GET /projects`: state=active|archived|all, пагинация.
- `POST /projects`: name; обязательно заголовок Idempotency-Key с UUID.
- `GET /projects/{id}`: свой проект, включая архив.
- `PATCH /projects/{id}`: name, expected_version.
- `POST /projects/{id}/archive` и `/restore`: expected_version.

Поля проекта: id, uuid, version, name, archived_at, updated_at.

## Задачи и чек-лист

- `GET /tasks`: state=active|archived|trashed|all; фильтры project_id, column, status=todo|doing|done, q (название), пагинация. По умолчанию активные задачи; не запускает генератор повторов в рамках чтения.
- `GET /tasks/{id}`: своя задача, включая архив/корзину.
- `POST /tasks`: title, необязательные project_id, description, status, column, priority, due_date, planned_date, checklist. Обязателен Idempotency-Key (UUID).
- `PATCH /tasks/{id}`: изменяемые поля выше и обязательный expected_version. Чек-лист передаётся целиком: массив {text,done}, до 100 пунктов. Архивную задачу/проект сначала восстановить.
- `POST /tasks/{id}/move`: column, before_id (null = конец), expected_version.
- `DELETE /tasks/{id}`: expected_version; только корзина, не безвозвратное удаление.
- `POST /tasks/{id}/archive` и `/restore`: expected_version.

Ответ задачи: id, uuid, version, project_id, title, description, status, column, priority, due_date, planned_date, checklist, sort_order, labels, comments_count, attachments_count, archived_at, deleted_at, updated_at. title до 240, description до 20 000; priority normal|high. column — ключ столбца, status — семантический тип. Если переданы оба, выбранный столбец определяет тип. Неизвестный/чужой столбец недоступен.

Версия увеличивается и при правках через веб-интерфейс, запуске таймера со сменой типа, архиве/восстановлении. Перенос может изменить версии других задач переставленного столбца; после переноса обновить его список. Запрос с устаревшей версией получает 409 и не перезаписывает данные. Это основа контроля конкуренции, не полноценный протокол офлайн-синхронизации SD-018.

Повтор создания проекта/задачи с тем же Idempotency-Key и тем же содержимым возвращает первоначальный ответ 201; другой запрос с тем же ключом даёт 409. Ключи общие для аккаунта, не отдельных маршрутов. Копии не создаются. Это не обновление уже существующей записи.

## Столбцы

`GET /columns`: key, name, kind, sort_order.
`PUT /columns`: массив columns из {key,name,kind}, до 20; новый столбец key=null. Действуют те же ограничения, что в вебе: базовые три остаются, тип созданного не меняется, занятый столбец (включая архив/корзину) не удаляется. Проверка версии всего набора столбцов пока не добавлена; синхронизация порядка между офлайн-устройствами — SD-018/019.

## Время

`GET /timer`: текущая активная/приостановленная сессия, elapsed_seconds, task_seconds, server_now.
`POST /tasks/{id}/timer`: request_key (UUID), идемпотентный старт; использует единый активный таймер аккаунта.
`POST /timer/{session}/stop`: reason=pause|stop, адресует конкретную свою сессию, не останавливает новую чужую сессию этого же аккаунта.
`GET /tasks/{id}/time`: вся история сессий с пагинацией (не последние 30); id, task_id, started_at, ended_at, duration_seconds, end_reason. Для активной сессии duration_seconds ещё не зафиксирована — живое время брать из /timer.

Ручная корректировка времени, операции с файлами/комментариями/метками, расписаниями и уведомлениями в публичный API этого этапа не включены. Существующий веб-функционал сохранён. Следующие клиенты расширят контракт отдельными задачами.
