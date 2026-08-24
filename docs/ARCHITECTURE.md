# Архитектура Mattermost Flutter

## Цели и ограничения

Клиент поддерживает Android, iOS, Web, macOS и Windows из одной кодовой базы.
Он должен показывать локальные данные сразу после запуска, оставаться полезным
без сети и обновляться по мере поступления REST/WebSocket данных. Ни сетевой
запрос, ни JSON-декодирование, ни запись большого пакета данных не должны
блокировать UI isolate.

Официальный Mattermost API v4 является внешним контрактом. Flutter-клиент не
должен копировать внутреннюю архитектуру React Native клиента; тот используется
как источник продуктового поведения и сценариев совместимости.

## Общая схема

```text
Widgets / adaptive layouts
        │ watch / commands
        ▼
Riverpod controllers (presentation)
        │ use cases
        ▼
Domain repositories (interfaces + domain models)
        │
        ▼
Repository implementations ────────────── Sync coordinator / Outbox
        │ local source                          │
        ▼                                       ▼
Drift reactive DAOs  ◀── transaction ── MattermostApi + WebSocketGateway
        │                                      │
        ▼                                      ▼
SQLite / IndexedDB-OPFS                   Mattermost API v4
```

Ключевое правило потока данных: **экран наблюдает локальную БД, а не результат
HTTP-запроса**. Репозиторий сначала отдаёт сохранённое значение и параллельно
запускает refresh. Успешный refresh атомарно пишет данные и sync metadata в БД;
Drift stream сам обновляет UI. Ошибка refresh отображается неблокирующим
индикатором, не уничтожая уже показанные данные.

## Модули и зависимости

Структура организована вертикальными feature slices:

```text
lib/
  main.dart
  src/
    app.dart
    core/
      api/             # REST boundary, Dio implementation, errors, auth
      database/        # Drift database, migrations, platform connection
      realtime/        # WebSocket connection, parsing, reconnect
      sync/            # refresh policies, cursors, outbox, conflict policy
      security/        # token storage and redaction
      routing/         # go_router configuration and deep links
      ui/              # breakpoints, theme, shared widgets
    features/
      auth/
      teams/
      channels/
      posts/
      threads/
      search/
      files/
      settings/
        domain/        # entities, repository contracts, use cases
        data/          # DTO/mappers, repository implementation, DAO/API use
        presentation/  # Riverpod controllers, pages, widgets
test/
  unit/ integration/ widget/ golden/
```

Допустимые зависимости направлены внутрь:

```text
presentation -> domain <- data -> core infrastructure
```

Domain не импортирует Flutter, Dio, Drift или JSON DTO. Presentation не знает о
Dio/SQL. HTTP разрешён только реализациям в `core/api` и data source. Между API
DTO, строками БД и domain entity обязательны явные mapper-функции.

## Выбор библиотек

| Задача | Решение | Причина |
|---|---|---|
| State/DI | `flutter_riverpod` | async state, dependency overrides, точечные rebuild |
| REST | `dio` | interceptors, timeout, cancellation, upload/download progress |
| Локальная БД | `drift` + SQLite | реактивные запросы, транзакции, миграции, native + WASM web |
| Секреты | `flutter_secure_storage` | Keychain/Keystore и реализации для desktop/web |
| Навигация | `go_router` | URL/deep links и Router API для Web/Desktop |
| Realtime | `web_socket_channel` | общий WebSocket API по платформам |
| Connectivity hint | `connectivity_plus` | триггер повторной синхронизации, но не доказательство интернета |
| Serialization | `json_serializable` | типизированные DTO без runtime reflection |

`connectivity_plus` не используется для запрета запросов: доступность сети
определяется только результатом самого запроса. Пакет даёт сигнал ускорить retry.

## Offline-first и синхронизация

### Чтение

1. DAO stream немедленно возвращает сохранённые записи.
2. Controller, не ожидая refresh для построения экрана, просит repository
   обновить stale данные.
3. Repository передаёт `If-None-Match` при наличии ETag и использует
   инкрементальные API/временные маркеры там, где Mattermost их предоставляет.
4. Ответ валидируется и сохраняется одной транзакцией.
5. Stream выдаёт обновлённый snapshot; scroll/focus не сбрасываются.

Каждая коллекция хранит `lastSyncedAt`, ETag/cursor и признак полноты пагинации.
Freshness policy различается: открытый канал обновляется активно, архивные данные
— лениво. Кнопка refresh всегда может принудительно обойти TTL.

### Запись и outbox

Пользовательские операции сначала фиксируются локально с `client_id`, состоянием
`pending` и записью outbox в одной транзакции. UI сразу показывает оптимистический
результат. Worker отправляет операции последовательно в пределах канала, но может
параллельно обслуживать независимые каналы. Состояния: `pending`, `sending`,
`sent`, `retryableFailure`, `permanentFailure`.

- Повторы используют exponential backoff с jitter и учитывают rate limit.
- Создание сообщений идемпотентно благодаря стабильному client id.
- Удаление/редактирование сверяется с server update timestamp.
- При конфликте серверная версия сохраняется, локальная правка не теряется и
  предлагается пользователю для повторного применения.
- Logout удаляет токен; удаление кеша конкретного аккаунта выполняется отдельно
  и явно.

### WebSocket

После первичной гидратации WebSocket подключается к `/api/v4/websocket`.
Последовательность событий проверяется; при разрыве или пропуске выполняется REST
reconciliation. Событие никогда не меняет UI state напрямую: оно проходит
normalization и транзакционно обновляет БД. Reconnect использует backoff, а смена
app lifecycle/сети служит сигналом переподключения.

## Схема локальных данных

Минимальный первый набор таблиц:

- `accounts`, `users`, `teams`, `team_members`;
- `channels`, `channel_members`, `channel_preferences`;
- `posts`, root-only `post_order`, raw `channel_history_entries`, `threads`,
  `files`;
- `sync_cursors`, `outbox`, `failed_operations`.

Все tenant-данные имеют `account_id`; уникальные ключи включают его, чтобы
несколько серверов с пересекающимися Mattermost id не конфликтовали. Для списков
не полагаемся только на `create_at`: таблицы порядка хранят серверную позицию.
Удаления представлены tombstone до завершения reconciliation.

На Android/iOS/macOS/Windows Drift открывает SQLite в background isolate. Web
использует `WasmDatabase` и worker, с OPFS при наличии и IndexedDB fallback.
Тяжёлый JSON parsing/нормализация больших ответов переносится в isolate через
`Isolate.run`/`compute`; данные пишутся пакетами в транзакции.

## API слой

`MattermostApi` — единственная REST-точка входа для репозиториев. Реализация на
Dio отвечает за base URL `/api/v4`, bearer auth, timeout, cancellation, ETag,
rate-limit metadata и преобразование HTTP/Mattermost ошибок в типизированные
ошибки приложения. Логи не содержат token, cookie, message body или персональные
данные.

API DTO отражают wire format и могут меняться с версией сервера. Перед login
клиент читает server version/config и включает capability flags; это позволяет
поддерживать несколько серверных версий без `if version` в UI.

Каждый метод `MattermostApi` возвращает конкретный DTO или типизированную
коллекцию DTO. Возвраты `Object`, `dynamic` и необработанные JSON-map запрещены.
Вложенные структуры ответа также имеют собственные DTO; открытые property bags
Mattermost представлены типизированным JSON-деревом. Декодирование сырого JSON
остается приватной деталью Dio-реализации и валидирует тип каждого известного
поля на границе API.

## Адаптивный интерфейс

Макет определяется доступной шириной через `LayoutBuilder`, а не типом устройства:

- compact `< 600`: один основной pane, drawer/bottom navigation;
- medium `600–839`: navigation rail + один content pane;
- expanded `>= 840`: постоянная навигация и content; при достаточной ширине —
  отдельный thread/info pane.

Точные пороги являются design tokens и уточняются вместе с макетами. Ввод
поддерживает touch, mouse, keyboard shortcuts, focus traversal и screen readers.
Состояние выбранного team/channel хранится в URL, где это применимо.

## Асинхронность и обработка ошибок

- Никаких синхронных filesystem/SQLite вызовов в UI isolate.
- Каждый Future либо `await`-ится, либо явно регистрируется как unawaited с
  централизованной обработкой ошибки.
- Поиск и быстро меняющиеся запросы отменяют предыдущий Dio `CancelToken`.
- Loading различает `initialLoading` (кеша нет) и `refreshing` (данные есть).
- Ошибки классифицируются: auth, permission, validation, rate limit, network,
  server, incompatible server, unknown.
- Background work ограничен очередями и batch size; бесконтрольный `Future.wait`
  запрещён.

## Безопасность

Токены хранятся только в secure storage. БД содержит несекретные нормализованные
данные и может быть дополнительно зашифрована после отдельного threat-model
решения. Сертификаты проверяются платформой; пользовательские CA и pinning —
отдельная enterprise capability. URL сервера валидируется, production по
умолчанию требует HTTPS. HTML/Markdown Mattermost рендерится безопасным parser-ом,
внешние ссылки проходят подтверждение/allowlist policy.

## Тестирование и поставка

- Unit: mappers, repositories, sync/outbox, conflict and retry policies.
- DAO/migration: in-memory SQLite и upgrade каждой сохранённой schema version.
- API contract: fixture responses разных поддерживаемых Mattermost versions.
- Widget/golden: compact/medium/expanded, light/dark, text scale 2x.
- Integration: cold offline launch, reconnect, pagination, WebSocket gap, logout.

CI запускает format, analyze, tests, code generation consistency и сборку каждой
платформы на подходящем runner. Этапы реализации: auth/capabilities → teams and
channels → posts/threads → realtime → outbox writes → search/files/notifications.
