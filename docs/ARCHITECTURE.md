# Архитектура Mattermost Flutter

## Приоритет актуальности

Клиент поддерживает Android, iOS, Web, macOS и Windows. Для рабочих сообщений
актуальность важнее автономного доступа, поэтому навигация каналов, посты, треды
и их пагинация используют network-first модель и живут только в памяти открытого
экрана.

При каждом входе в канал клиент запрашивает последнюю страницу
`GET /channels/{channel_id}/posts`. Закрытие экрана освобождает его Riverpod
state; повторный вход снова начинается с конца истории. Ошибка первого запроса
показывает retry-state, а ошибка подгрузки старых сообщений сохраняет уже
показанную историю.

Drift остается инфраструктурной границей для будущих долговечных данных,
например профилей пользователей. Сообщения, треды, сайдбар и sync metadata в
Drift не сохраняются.

## Общая схема

```text
app ── bootstrap, router, theme and localization
 │
 ├──────────────────────────────────────► ui
 │                                         │ widgets, controllers and
 │                                         │ volatile view state
 │                                         ▼
 │                               domain repository contracts
 │                                         ▲
 │                                         │ domain entities and policies
 └── data/providers ──────────────────────┘
       │ constructs implementations
       ▼
data ── raw MattermostApi/DTO, Drift, cache, secure storage,
        platform adapters and repository implementations
       ▼
Mattermost API v4

AppDatabase (Drift) ── account-scoped user-profile cache
```

Направление продуктовых зависимостей — `ui → domain ← data`: presentation не
вызывает HTTP, WebSocket, DAO или secure storage напрямую. Контроллер обращается
к domain-контракту репозитория; data-реализация получает DTO через
`MattermostApi` и явно преобразует их в domain entities. Единственное
разрешённое пересечение UI и data — публичные handles в `data/providers`,
возвращающие domain-типы.

Provider wiring инфраструктуры и repository contracts находится в
`data/providers`, а UI projections — в `ui/ui_providers.dart`. UI-классы
получают только domain-контракты через конструкторы. Auth-репозиторий владеет единственным
закрываемым `MattermostApi` активного аккаунта. Он читает secure storage один раз
при восстановлении сессии или использует только что введенный PAT, а logout и
смена сервера закрывают Dio вместе с его connection pool. Feature-repository
получают уже аутентифицированный API и не имеют доступа к токену.

### Проверяемые границы импортов

`import_rules` превращает основные границы этой схемы в проверку анализатора:

- `domain` не импортирует `data`, `ui`, `app`, Flutter, Riverpod, Dio или Drift;
- `data` не импортирует `ui`, а `data/api` не импортирует domain;
- `ui` может импортировать только публичный мост `data/providers` и не может
  обращаться к data implementation напрямую;
- `ui/core` не зависит от Mattermost domain/data и остаётся generic UI слоем;
- `app` может использовать `data/providers`, но не data infrastructure.

Правила находятся в `analysis_options.yaml` и обязательны для `dart analyze`
(запускайте его в CI наряду с обычным `flutter analyze`). Плагин требует Dart
3.10+ (Flutter 3.38+); после изменения блока `plugins` перезапустите Dart
Analysis Server в IDE.

## Модули и зависимости

Продуктовый код разделён по владельцам ответственности:

```text
data/      # raw API/DTO, БД, cache, platform services и repository implementations
domain/    # entities, policies, use cases и repository contracts
ui/        # controller/view state и widgets, сгруппированные по UI-сценарию
```

Зависимости направлены внутрь:

```text
ui -> domain <- data
```

Domain не импортирует Flutter, Riverpod, Dio, Drift или API DTO. Все REST-вызовы
проходят через `MattermostApi`; Dio создается только в data API wiring.

Общие модели сообщений и их DTO mapping находятся в root `domain` и `data`.
Posts и threads не импортируют internals друг друга. Единая domain policy выбора
display name находится в `domain/policies`; avatar initials находятся в
`ui/core`, а author/time/Markdown primitives — в `ui/messages`.

## Посты и пагинация

- Последняя страница загружается с `page=0&per_page=60`.
- Более старая история загружается через `before=<raw_post_id>`.
- Курсор берется из последнего id в сыром `PostList.order`, а не из последнего
  видимого root-поста. Поэтому страницы, содержащие только replies, не приводят
  к пропускам или циклам пагинации.
- Ответ канала фильтруется до root-постов после маппинга. Replies показываются в
  отдельном треде.
- До фильтрации replies группируются по `root_id`; их id и максимальный
  `create_at` хранятся в состоянии открытого канала. Для root используется
  максимум из серверного `reply_count` и числа уникальных замеченных replies.
  Это восстанавливает affordance треда даже при устаревшем нулевом summary или
  когда reply и root оказались на разных страницах.
- Контроллер объединяет страницы по `post.id` и сортирует по `create_at`, затем
  по id. Состояние освобождается при закрытии канала.

## Навигация по permalink поста

Ссылки активного сервера вида `/<team-name>/pl/<post-id>` перехватываются
Markdown-слоем и не передаются внешнему браузеру. Ссылки другого origin и
остальные HTTP(S)-ссылки сохраняют обычное внешнее поведение. Перед переходом
клиент получает `GET /posts/{post_id}` и `GET /channels/{channel_id}`, чтобы
разрешить целевой канал, root/reply-состояние и необходимость открыть тред.

Исторический переход использует тот же volatile `ChannelPostsController`, что и
обычная лента, но заменяет его снимок ограниченным окном: параллельно
запрашиваются страницы `before=<root_post_id>`, `after=<root_post_id>` и сам
root-пост. Окно имеет независимые курсоры старой и новой границ; приближение к
любой границе догружает соответствующее направление и сливает посты через
обычную canonicalization policy. Обычный вход в канал по-прежнему начинает с
последней страницы и использует только пагинацию назад.

Каждый permalink открывается отдельным route `/post/:postId`, в location
которого входит только id поста. Route-scoped presentation controller разрешает
цель, показывает initial loading/error с retry и отменяет запрос при pop. Это
не меняет global shell state: исходный route остаётся смонтированным ниже
permalink route и сохраняет свой snapshot, scroll position, focus и composer
draft. Даже ссылка на тот же канал или тред использует отдельный route-scoped
volatile provider, поэтому historical focus не заменяет snapshot источника;
после pop providers цели освобождаются.

На wide layout permalink показывает целевой канал с выделенным root; если
целью является root с replies или reply, рядом открывается side-thread, а reply
дополнительно выделяется и прокручивается в видимую область. Крестик
side-thread закрывает только его, тогда как Back в заголовке канала снимает
permalink route. На compact layout permalink без треда показывает канал, а
permalink c тредом сразу показывает fullscreen `ThreadPane` без скрытого или
промежуточного канала. Его Close, system Back, edge-swipe, Escape и header Back
снимают весь permalink route и возвращают ровно к экрану-источнику.

## Поиск сообщений

Search — самостоятельный network-first экран с volatile Riverpod state. В нём
живут черновик и отправленный запрос, результаты, подсказки, курсоры и ошибки;
закрытие экрана освобождает это состояние. Результаты, история запросов,
подсказки и metadata поиска не записываются в Drift и не изменяются событиями
WebSocket: поиск представляет точечный серверный снимок и обновляется только
явным refresh.

Поиск команды проходит через `POST /teams/{team_id}/posts/search` в
`MattermostApi`; подсказки каналов — через
`GET /teams/{team_id}/channels/search_autocomplete`, а `from:` переиспользует
ограниченный autocomplete пользователей. Репозиторий восстанавливает порядок
из ответа сервера, сохраняет и root posts, и replies, batch-загружает авторов,
ограниченно догружает отсутствующие каналы и маппит сообщения общим mapper-ом.
Текст запроса и содержимое сообщений не попадают в diagnostics или логи.

Первая страница запрашивается с `page=0` и `per_page=60`. Следующая страница
допустима только пока сервер возвращает новые id и новый fingerprint порядка:
это предотвращает цикл на SQL backend, где пагинация поиска может быть
неподдерживаемой. Ошибка refresh или pagination сохраняет уже показанные
результаты и даёт локальный retry.

Search destination и действие «Search in channel» передают только launch intent:
оно может подставить канонический `in:` token и сфокусировать поле, но не
запускает пустой запрос. Нажатие результата использует существующий permalink
route. Поэтому authoritative resolution поста и канала, а также поведение для
root/reply на compact и wide layouts, остаются едиными; Back возвращает к
сохранённым query, результатам и позиции прокрутки Search.

## Отправка сообщений

Текстовые сообщения и ответы отправляются через `POST /api/v4/posts`. Для
ответа запрос содержит `root_id`; `pending_post_id` создаётся composer-ом и
повторно используется при ручном retry неизменённого черновика. Пока отправка
выполняется, повторный submit блокируется.

Канал и тред используют один `MessageComposer`: Enter отправляет сообщение,
Shift+Enter добавляет новую строку. Черновик очищается только после успешного
REST-ответа и сохраняется вместе с неблокирующей ошибкой при неудаче.

На touch-устройствах открытый тред использует собственную политику жестов:
одиночный тап по сообщению открывает действия, а долгий тап остаётся за нативным
выделением текста. Его контекстное меню начинает с `Quote`; выбранный видимый
текст вставляется в composer как Markdown-цитата с `> ` на каждой строке.
Лента канала сохраняет обычные tap-to-thread и long-press-to-actions жесты.

### Markdown-редактор composer-а

Визуальный Markdown-редактор является presentation-scoped частью
`MessageComposer`; он не получает API, WebSocket, DAO или secure storage и не
создаёт durable draft/cache. Его единственный editable source — raw Markdown
в `TextEditingValue`; server wire text должен совпадать с ним побайтно, кроме
уже существующей сериализации атомарных mentions и custom emoji при
copy/cut/send. Редактор не выполняет Markdown round-trip и не нормализует
пользовательские пробелы, номера списков или delimiters.

`MessageEditorController` владеет native value, selection и composing range.
Его parser и команды — pure Dart, а visual projection строит spans из того же
editing buffer. В Live Preview (режим по умолчанию) завершённый неактивный
inline/block marker остаётся в span plain text с нулевым visual advance, кроме
list prefix: `- `, `* ` и `1. ` остаются видимыми и создают естественный
отступ пункта; поэтому
`span.toPlainText()` совпадает с `TextEditingValue.text`, а visibility не
переписывает value, selection или IME composing range. Панель форматирования
применяет pure commands к raw source и не получает доступ к transport/data
слоям.

Режим `source` уже существует на уровне controller, но пользовательского
переключателя и persistent preference пока нет. Общие parity fixtures editor-а
и `MattermostMarkdown`, а также ручная platform-матрица native selection/IME
ещё не завершены. Подробные правила active marker и offset model находятся в
`docs/MESSAGE_EDITOR_PLAN.md`.

Собственный post из REST-ответа сразу добавляется в volatile state открытого
канала или треда. Inbox дополнительно использует аутентифицированный
`SessionRealtimeService`: он владеет единственным `WebSocketGateway` активной
сессии и раздаёт декодированные transport-сигналы repository-подписчикам.
Transport отвечает за reconnect и sequence gaps; Inbox-фильтр пропускает только
его события и известные пользователю каналы, а domain policy сливает
типизированные post-дельты с тем же canonicalization/grouping pipeline, который
строит исторический REST snapshot. `post_edited` и `ephemeral_message` для
interactive actions идут через тот же socket. События здорового соединения
никогда не запускают HTTP snapshot reload: полный network-first recovery
выполняется только после reconnect или пропуска WebSocket sequence без потери
уже показанного состояния. Ephemeral-события при recovery не восстанавливаются.

## Legacy interactive messages

Legacy rich content принадлежит общей модели поста, а не отдельной feature-
копии. Transport DTO безопасно читает `props.attachments`, сохраняя исходные
неизвестные данные только на data-стороне; mapper переводит валидные attachment,
field и action в immutable domain-типы `RichAttachment`. Секретный
`integration.context` не экспортируется из transport. Общий `MessageContent`
рисует одну и ту же карточку в channel, thread, permalink и Inbox, а файловые
`PostAttachment` остаются отдельной моделью.

Выполнение legacy action проходит по одной цепочке:

1. Auto-disposed presentation state регистрирует инициировавший control по
   scope/post/action и блокирует только его.
2. Domain `PostActionRepository` принимает opaque cookie и выбранное значение;
   data-реализация вызывает `POST /posts/{post_id}/actions/{action_id}` только
   через `MattermostApi`.
3. После успешного dispatch repository всегда перечитывает post через
   `GET /posts/{post_id}` и возвращает authoritative domain `Post` вместе с
   безопасным `goto_location`.
4. Владелец открытого channel/thread/permalink snapshot заменяет запись по id
   через `mergePosts`. Поэтому REST refresh и поздний `post_edited` используют
   одну canonical replacement policy: дубликат не появляется, актуальное
   содержимое заменяется, а более сильные `reply_count` и `last_reply_at`
   сохраняются.

System-backed attachment selects (`data_source: users/channels`) используют
отдельный domain query и server-side `POST /users/search` либо
`POST /channels/search`. Результат ограничен 50 элементами, superseded запрос
отменяется вместе с auto-disposed provider, а UI отправляет Mattermost ID как
`selected_option`.

`SessionRealtimeService` владеет ровно одним `WebSocketGateway` активной сессии
и делает fan-out transport-сигналов в Inbox и post-action repositories. Каждый
consumer фильтрует и типизирует только нужные ему события; открытие карточки,
канала или треда не создаёт дополнительное WebSocket-соединение. Reconnect,
backoff и sequence-gap detection остаются общей transport-ответственностью.

Перед выполнением action presentation регистрирует только инициировавший
control по scope/post/action и ожидаемому channel/root. Серверный
`ephemeral_message` содержит ephemeral post с `root_id` исходного action root;
первый подходящий pending control атомарно забирает событие и показывает текст
рядом с карточкой. Feedback хранится только в auto-disposed состоянии экрана,
не попадает в Drift, логи или durable cache и не восстанавливается через REST
после reconnect/gap. Непривязанное или просроченное ephemeral-событие
отбрасывается: оно не должно мигрировать к соседнему control или другому экрану.
Поздний `post_edited` маппится общим message mapper и передаётся владельцу
открытого snapshot через тот же action presentation pipeline.

## Треды

Пункт Threads в сайдбаре загружает список отслеживаемых CRT-тредов через
`GET /users/{user_id}/teams/{team_id}/threads` страницами по 60 элементов с
`extended=true`. Root post, счетчики replies/unread/mentions и участники приходят
одним ответом; отсутствующие среди participants авторы root-постов дополняются
одним batch-запросом `/users/ids`. Пагинация использует `before=<root_post_id>`.
Список не вызывает endpoint полного треда для каждого элемента.

Открытие треда вызывает `GET /posts/{post_id}/thread`. Репозиторий использует
`direction=up` и проходит серверный `next_post_id` через `fromPost` и
`fromCreateAt` до `has_next=false`, после чего возвращает root с replies одним
domain-снимком. Повторяющийся или некорректный курсор завершает загрузку ошибкой,
не показывая частичный тред. Replies сортируются по `create_at`, затем по id;
редактирование поста не меняет порядок. Удаленный reply сохраняет позицию и
показывается placeholder-ом. Для followed thread граница последних
`unread_replies` отмечается divider-ом, который становится начальной позицией
скролла. После первого кадра полного треда read timestamp обновляется отдельным
API-вызовом до времени, зафиксированного перед первой страницей загрузки.
Если непрочитанных replies нет, при открытии из пункта Threads начальная позиция
скролла устанавливается в конец треда. При открытии из списка постов канала
тред остается на начальной позиции у root post.
При ширине от `AppBreakpoints.sideThread` тред остается боковой панелью рядом
со списком. На более узком layout тот же `ThreadPane` открывается маршрутом
`/thread/:rootPostId`: системный Back Android и edge-swipe iOS возвращают к
исходному списку, не создавая отдельный мобильный виджет. Закрытие панели или
маршрута освобождает снимок.

## Сайдбар

Сайдбар при входе загружает первую команду пользователя, ее каналы и категории.
Имена direct/group диалогов дополняются через users API. Результат хранится в
контроллере; ручной refresh сохраняет текущий снимок на экране до успешного
ответа и показывает неблокирующую ошибку при неудаче.
Поиск в сайдбаре локально фильтрует уже загруженный снимок по отображаемому
имени канала или диалога. Совпадения остаются внутри исходных
категорий; во время поиска подходящие категории раскрываются, а после очистки
восстанавливается их предыдущее состояние.

Direct-диалоги также получают versioned-ссылку на профиль собеседника из того
же batch-ответа users API. Видимые строки ленивого списка сразу показывают
инициалы, а байты аватара запрашивают асинхронно через общий `UserRepository` и
тот же account-scoped cache, что сообщения и карточка профиля. Отдельного
thumbnail endpoint у Mattermost для аватара нет: размер декодирования
ограничивается уже в UI. Ошибка изображения не мешает навигации и оставляет
fallback с инициалами.

На compact layout вкладки Channels и Inbox открываются как отдельные экраны.
На medium и expanded layout постоянный navigation rail остается на месте, а
выбранная вкладка занимает левую панель: список каналов показывается только в
Channels, Inbox заменяет его панелью шириной 380 пикселей. Открытый из Inbox
тред занимает соседнюю рабочую область, не закрывая сам Inbox.

Inbox отображает сообщения в секциях Mentions, Bots & integrations, Direct
Messages и Threads. Новые личные сообщения одного автора в одном диалоге
объединяются: одиночная запись показывает текст и открывает тред, а пачка из
двух и более сообщений показывает счетчик и открывает диалог внутри контекста
Inbox. На широком layout Inbox остается слева, диалог занимает рабочую область,
а открытый из него тред может стать третьей панелью. На compact layout диалог
открывается поверх Inbox, поэтому Back возвращает в Inbox, а не в Channels.
Read продвигает
границу просмотра всего канала, а postpone переносит только последнее сообщение
пачки по его post ID. Postponed остается отдельной очередью конкретных post ID,
поэтому один диалог может одновременно присутствовать в New и Postponed.
Упоминание в новом reply имеет приоритет Threads; без него тред сохраняет
источник root-поста — Mentions или Direct Messages. Для CRT-треда read обновляет
thread read timestamp в команде, из которой этот тред был загружен.

После успешного REST snapshot Inbox асинхронно открывает WebSocket и показывает
в заголовке зеленый/красный индикатор состояния. Realtime mention в первой
версии определяется только по `@username` текущего пользователя; DM/GM
доставляются целиком, а обычные каналы дополнительно учитывают effective
all-messages notification policy. Первый connect только обновляет индикатор;
reconnect и пропуск `seq` запускают атомарную сверку с REST.

Inbox controller живет на уровне авторизованной оболочки, а не открытой вкладки:
переходы между Channels, Inbox и тредами не закрывают его realtime-подписку.
Возврат приложения в `resumed` принудительно заменяет потенциально полуоткрытый
WebSocket и запускает REST-сверку; появление доступной сети также прерывает
текущий reconnect/backoff и создает новое соединение. Новая подходящая realtime
коммуникация атомарно обновляет Inbox и его навигационный индикатор, а оболочка
показывает foreground SnackBar. Initial snapshot, reconnect-сверка, edit/delete
и повторная доставка одного post id не создают in-app уведомление. Системные
push-уведомления остаются отдельной ответственностью.

## Профили и аватары пользователей

Запросы профилей по ID используют DB-first cache внутри `UserRepository`.
Таблица хранит scope активного server/account, user id, имя, фамилию, логин,
nickname, должность, email, версию изображения и время истечения. Scope включает
URL сервера и ID вошедшего пользователя,
поэтому аккаунты одного сервера не видят кэш друг друга. Свежая запись
используется локально; отсутствующие и истекшие записи одним batch-запросом
загружаются через `POST /users/ids` и получают TTL 7 дней.
Пакетное чтение из Drift не превращается в последовательность одиночных
запросов. Ошибка обновления истекшей записи не подменяется stale-данными.

Этот профильный cache не хранит bytes аватара. Сохраненная версия изображения
передается avatar repository и участвует в его versioned cache key.

Карточка пользователя открывается по нажатию на аватар автора. Ее
auto-disposed provider параллельно получает свежий профиль напрямую через
`GET /users/{user_id}` и актуальный presence через
`GET /users/{user_id}/status`. Одиночный запрос карточки всегда обходит batch
cache, чтобы не показывать устаревшие или добавленные миграцией пустые поля.
Ошибка первой загрузки показывает retry-state. Кнопка Message вызывает
`POST /channels/direct` с ID
текущего и выбранного пользователей, затем выбирает полученный direct-канал и
обновляет сайдбар. Этот переход всегда сбрасывает route stack до оболочки и
открывает канал из секции Channels: на wide layout одновременно видны sidebar и
диалог, а на compact layout Back из диалога возвращает к списку каналов.

Упоминания `@username` в постах и replies разрешаются одним batch lookup для
уникального набора имен. Свежие профили читаются из account-scoped Drift cache;
известная, но истекшая запись обновляется через `/users/ids`, а отсутствующее в
cache имя проверяется через `/users/usernames`. Только существующий пользователь
заменяется на кликабельное `@First Last`, открывающее ту же карточку профиля.
Ошибки и неизвестные имена сохраняют исходный текст. Те же уникальные handles
одним запросом проверяются через `POST /groups/names`: существующая user group
остаётся кликабельным `@group-handle` без замены на display name. Нажатие на неё
пока не открывает карточку или список участников.

User DTO сохраняет `last_picture_update`; для bot-аккаунта версия изображения
берется из `bot_last_icon_update`. Message mapper переносит эту версию в автора
поста. Само изображение загружается авторизованным
`GET /users/{user_id}/image?_=<version>` только через `MattermostApi`.

`UserRepository` владеет временным cache изображений на базе
`flutter_cache_manager`. Ключ содержит server/account id, user id и версию
изображения. Поэтому сообщения одного автора разделяют один cache entry и один
in-flight запрос, а смена аватара создает новый ключ без ручной инвалидации.
Cache ограничен 500 объектами и очищается по неиспользованию; на Web библиотека
дает session-memory cache, на native/desktop — временный file cache. Токен не
передается в widget или сторонний HTTP-клиент.

### Профиль текущего пользователя и статусы

Профиль текущего пользователя является отдельным network-first feature slice.
Он параллельно получает `GET /users/me` и `GET /users/{user_id}/status`, а
команды проходят через `CurrentUserProfileRepository`. Availability обновляется
через `PUT /users/{user_id}/status`; диалог срока показывается только для DnD,
а `dnd_end_time` передается в Unix seconds, как требует Mattermost API. Away и
offline устанавливаются без срока, поскольку сервер не поддерживает их
автоматический сброс.

Custom status устанавливается и сбрасывается через `PUT`/`DELETE
/users/{user_id}/status/custom`. Отдельного read endpoint у API нет, поэтому
текущее значение явно маппится из JSON-строки `user.props.customStatus`.
Истекшее или некорректное значение не показывается. Profile state не сохраняется
в Drift: повторный вход и перезапуск всегда начинают с актуального server
snapshot.

Logout сначала пытается отозвать активную серверную сессию через
`POST /users/logout`, затем независимо от результата удаляет локальный токен из
secure storage и закрывает API client. Поэтому отсутствие сети не может оставить
учетную запись открытой в приложении.

Пока bytes загружаются и при любой ошибке UI сохраняет цветной круг с
инициалами. После загрузки Flutter асинхронно декодирует уменьшенное под размер
виджета изображение и заменяет fallback без блокирующей операции в `build`.

## Custom emoji и расширение текста

Custom emoji из `PostMetadata.emojis` переносятся в domain-снимок сообщения.
Поэтому обычный путь отображения `:emoji_name:` не делает metadata lookup:
авторизованно загружается только `GET /emoji/{emoji_id}/image`. Если сервер не
прислал metadata, используется fallback `GET /emoji/name/{emoji_name}`.

Bytes живут во временном account-scoped cache на 5000 объектов; ключ включает
имя, id и `update_at`, а параллельные misses одного имени объединяются. Пока
cache/API выполняются, shortcode остается текстом, поэтому Markdown получает
первый layout без ожидания сети.

Кнопки custom emoji в списке реакций используют тот же provider и тот же cache,
что inline emoji. Нажатие оптимистично обновляет volatile снимок открытого канала
или треда, затем вызывает `POST /reactions`; повторное нажатие вызывает
`DELETE /users/{user_id}/posts/{post_id}/reactions/{emoji_name}`. При ошибке
REST-запроса локальное изменение откатывается, а уже показанный контент остается
на экране.

Picker реакций открывается как привязанный popover для точного указателя и как
последовательный bottom sheet после touch long-press. Системный каталог и его
алиасы генерируются из закрепленного Mattermost `emoji.json`, поэтому категории
и поиск по непрерывной подстроке shortcode работают локально без сетевой
задержки. Серверный
`POST /emoji/search` используется только для custom emoji после debounce 500 мс;
устаревший запрос отменяется, а его результат не может заменить более новый.
Страница custom-категории загружается через `GET /emoji` порциями по 90.

Метаданные custom emoji хранятся только в памяти активного repository: одинаковые
запросы объединяются, до 50 поисковых/страничных результатов живут 5 минут.
Изображения продолжают использовать временный versioned cache по `id/update_at`.
Последние 27 успешно выбранных emoji в picker или composer — отдельные durable UI
preferences в таблице `recent_emojis`; они содержат только account scope,
shortcode и timestamp последнего использования, не содержат post id или текста
сообщения и переживают перезапуск приложения. Повторный выбор обновляет одну запись
через upsert, порядок определяется по убыванию timestamp, а сверх лимита удаляется
только самая старая запись.

Composer распознаёт незавершённый `:shortcode` относительно текущей collapsed
каретки и открывает подсказки только после двух символов. Полноэкранный picker и
composer используют один query-driven компонент результатов: системный каталог
фильтруется синхронно, custom emoji добавляются через тот же отменяемый debounce-
поиск. На compact ширине сетка ниже, на medium/expanded ограничена шириной 560 px;
выбор поддерживает touch/mouse и клавиатуру (стрелки, Enter, Escape).

`MessageEditorController` — граница будущего rich-text ввода. Системные emoji
хранятся как Unicode, а custom emoji — как односимвольные inline-объекты с
визуальным `WidgetSpan`; перед отправкой и копированием они сериализуются обратно
в Mattermost shortcode. Поэтому API по-прежнему получает обычный текст, а будущая
подсветка Markdown может расширить `buildTextSpan`, не меняя submit-контракт.

`MattermostMarkdown` принимает декларативные inline replacements. Emoji — первый
consumer этого API; будущие замены наподобие `@username` добавляются через тот
же parser/builder boundary, не связывая общий Markdown renderer с feature data
или Riverpod.

## Вложения постов

Файлы из `PostMetadata.files` явно маппятся в общую domain-сущность сообщения и
не сохраняются локально. Thumbnail, preview и оригинал загружаются авторизованно
через `MattermostApi`; токен и прямой HTTP-клиент не передаются в widgets.
Одиночное изображение отображается крупным preview, а несколько файлов —
компактными карточками. Полноэкранный просмотр листает изображения одного поста.
Сохранение оригинала делегируется platform file saver через domain-контракт.
Для sandboxed macOS включен доступ к выбранному пользователем файлу, а iOS
экспортирует сохраненные документы в системное приложение Files.

## База данных

Schema version 7 удаляет прежние 11 таблиц сайдбара, постов, реакций, порядка и
sync metadata. Schema version 8 добавляет `cached_user_profiles`, владельцем
которой является `UserRepository`. Schema version 9 добавляет поля полной карточки
и версию аватара. Schema version 10 добавляет составной индекс по account id и
регистронезависимому username. Schema version 11 добавляет account-scoped MRU
shortcodes реакций `recent_emojis`. Профили разделены по account/server id и живут
7 дней; сообщения, треды, сайдбар и sync metadata по-прежнему не сохраняются.

Новые таблицы добавляются только вместе с явным владельцем данных, политикой
актуальности и причиной, по которой состояние должно переживать процесс.

## Адаптивность, безопасность и асинхронность

- Макет выбирается по доступной ширине через constraints, а не по платформе.
- Строка сообщения выбирает ветку взаимодействия по фактическому
  `PointerDeviceKind`, а не по платформе: `touch`, `stylus` и `invertedStylus`
  используют touch-сценарий, мышь сохраняет mouse-сценарий. При touch-сценарии
  подсветка не появляется на pointer down: она включается только после
  неподвижного удержания, распознанного стандартной gesture-системой Flutter,
  и сразу снимается при scroll, up, cancel, завершении long press и dispose.
  Tap по неинтерактивной поверхности открывает тред, а long press дает легкий
  системный haptic feedback и открывает панель действий. Мышь отдельно
  использует hover-подсветку, click и hover-панель быстрых действий; ее состав
  сокращается по доступной ширине, а не по типу платформы.
- Shell использует общие breakpoint-токены: до 700 px панели каналов и контента
  открываются последовательно, а основные направления `Channels` и `Threads`
  находятся в нижнем navigation bar; от 700 до 1119 px те же направления
  находятся в левом navigation rail рядом с сайдбаром и рабочей областью; от
  1120 px используется полный трехпанельный layout `navigation rail → channel
  sidebar → content`. Внутренняя боковая панель треда по-прежнему определяется
  собственной доступной шириной контента через `AppBreakpoints.sideThread`.
- Тела постов и ответов рендерятся общим `MattermostMarkdown`: GFM дополняется
  channel links, LaTeX, размерами inline-изображений и подсветкой кода. Полная
  матрица совместимости и URL-политика описаны в `docs/MARKDOWN.md`.
- Все user-facing строки локализуются вне widgets; поддерживаются keyboard,
  semantics, scalable text и light/dark themes.
- Токены хранятся только в secure storage и не попадают в Drift или логи.
- До входа auth workflow запрашивает `/config/client`: кнопка логина и пароля
  доступна только когда сервер включает вход по email или username. Пароль
  передаётся только в `POST /users/login`; полученный в заголовке session token
  проверяется и сохраняется тем же потоком, что SSO и персональный токен.
- Интерактивный SSO проходит через domain-контракт `SsoBrowserGateway`.
  Нативный browser adapter принимает только `MMAUTHTOKEN`, прочитанный native
  Cookie Manager после возврата на выбранный Mattermost origin; UI не получает
  cookies. Перед и после попытки очищаются только относящиеся к этому серверу
  `MMAUTHTOKEN`, `MMUSERID` и `MMCSRF`. Flutter Web явно возвращает
  недоступность embedded SSO, а не читает cross-origin HttpOnly cookies через
  JavaScript. WebView и Cookie Manager используют одно platform-default cookie
  store: Apple non-persistent store недоступен Cookie Manager этого плагина, а
  Android incognito очищает глобальные cookies вместо изоляции одной попытки.
- Большой JSON parsing переносится с UI isolate; запросы и пагинация имеют
  ограниченную конкуренцию и обязаны учитывать rate limits.
- Auto-disposed контроллер создает framework-neutral request scope. Его
  `ref.onDispose` отменяет связанные Dio `CancelToken`, не протаскивая Dio через
  domain-контракты.
- Каждый Future await-ится либо явно передается в централизованную обработку.

## Упоминания в composer

Autocomplete упоминаний — network-first, composer-scoped состояние: параллельные
результаты `/users/autocomplete` и `/groups` не попадают в Drift или профильный
cache и отменяются при смене каретки, destination или закрытии composer. Domain
repository возвращает server-authoritative секции channel members, referenceable
group mentions и users not in channel. Group query запрашивает
`filter_allow_reference=true` и `include_member_count=true`; недоступность
опционального лицензируемого group endpoint не скрывает подсказки пользователей.

Группы сортируются независимо от пользователей: exact handle, prefix handle,
prefix display name, затем case-insensitive handle. Принадлежность текущего
пользователя к группе не запрашивается и не влияет на ranking — это соответствует
официальным web/mobile-клиентам. В панели секция `Group Mentions` находится между
пользователями канала и `Not in channel`, а строка показывает display name и
количество участников.

Черновик хранит выбранного пользователя или группу как inline atom с одним object
replacement character в editable projection. Для пользователя видимая подпись —
`@Display Name`, а wire/clipboard-строка — `@username`. Для группы и видимая, и
wire/clipboard-строка равны неизменному `@group-handle`. Оба inline object
атомарно удаляются и не позволяют поместить каретку внутрь подписи.

## Проверка изменений

Изменения форматируются, проверяются `flutter analyze` и focused tests. Для UI
проверяются compact/expanded widths и большой text scale. При добавлении будущих
Drift-таблиц обязательны code generation, migration и migration test.
