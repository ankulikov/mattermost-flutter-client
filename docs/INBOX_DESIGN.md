# Inbox и Postponed

Статус: proposed  
Дата исследования: 2026-09-03  
Область: замена верхнеуровневого пункта Threads агрегированным Inbox

## Резюме решения

Inbox — это network-first проекция входящих коммуникаций, требующих внимания.
Он объединяет три независимых серверных источника:

1. непрочитанные отслеживаемые CRT-треды;
2. непрочитанные root-сообщения каналов, которые являются mention либо попадают
   под настройку оповещений обо всех сообщениях;
3. непрочитанные direct и group messages.

В UI остаются две очереди: `New` и `Postponed`. `New` не хранится локально и
каждый раз восстанавливается из REST snapshot с последующим обновлением через
WebSocket. `Postponed` хранит только ссылки на посты и дату добавления в
Mattermost user preferences; контент сообщений в preferences или Drift не
попадает.

Основная единица дедупликации — Mattermost post ID. Для треда канонический ключ
равен root post ID. Для DM-пакета UI объединяет несколько post ID, если
последовательные входящие сообщения одного автора разделены интервалом не более
двух минут.

Важное ограничение: стандартный API v4 не предоставляет единый notification
feed. Более того, cold-start REST snapshot содержит `mention_count`, но не
перечень post ID и причин, из-за которых каждый пост посчитан mention. Поэтому
абсолютно точное восстановление исторических mention после разрыва WebSocket
невозможно только по стандартному API. MVP может использовать описанную ниже
server-compatible классификацию с проверкой счетчиков; для строгой точности
нужен небольшой серверный endpoint/plugin, возвращающий unread attention post
IDs и причины.

## Цели

- Дать одну очередь входящих коммуникаций вместо отдельного Threads.
- Сохранить preview и переход в исходный канал, DM или тред.
- Поддержать отложенную обработку любого доступного сообщения.
- Не показывать один пост или тред одновременно в обеих очередях.
- Корректно работать после перезапуска, reconnect и пропуска WebSocket sequence.
- Явно разделять личные сообщения от людей и автоматизаций.
- Соблюсти текущую архитектуру `presentation -> domain <- data`, network-first
  политику и отсутствие локального персистентного message cache.

## Не входит в первую реализацию

- Изменение серверной модели read/unread Mattermost.
- Синхронизация полного текста сообщений между запусками приложения.
- Замена или редактирование официальных настроек уведомлений в первой версии.
- Напоминания по времени, due dates и сортировка пользователем.
- Использование passive highlight keywords (`highlight_keys`) как причины для
  попадания в Inbox: они подсвечивают текст, но не создают уведомление.

## Что уже есть в приложении

Текущий клиент уже умеет:

- получать CRT-треды через
  `GET /users/{user_id}/teams/{team_id}/threads`;
- пагинировать список тредов по `before=<root_post_id>`;
- получать полный тред через `GET /posts/{post_id}/thread`;
- отмечать тред прочитанным через
  `PUT /users/{user_id}/teams/{team_id}/threads/{thread_id}/read/{timestamp}`;
- получать каналы, посты и профили пользователей;
- различать `is_bot` в wire DTO.

Для Inbox пока отсутствуют:

- `WebSocketGateway` и обработка sequence gaps;
- channel membership DTO с `last_viewed_at`, `msg_count`,
  `msg_count_root`, `mention_count`, `mention_count_root` и `notify_props`;
- preferences API;
- REST методы follow/unfollow, view channel, posts around unread и posts by IDs;
- признак bot/automation в domain-моделях сообщения;
- агрегирующий feature-срез Inbox.

## Результаты исследования Mattermost

### Источники данных действительно разные

| Источник | Cold start / refresh | Realtime | Read action |
| --- | --- | --- | --- |
| CRT-тред | `GET /users/{user}/teams/{team}/threads?unread=true` | `thread_updated`, `thread_follow_changed`, `thread_read_changed` | `PUT .../threads/{root}/read/{timestamp}` |
| Канал | channel + channel member counters, затем unread posts | `posted`, `post_edited`, `post_deleted` | `POST /channels/members/{user}/view` |
| DM/GM | те же channel/member counters; тип канала `D` или `G` | то же событие `posted` | тот же `view` endpoint |
| Postponed | preferences категории `postponed_messages`, затем `POST /posts/ids` | `preference_changed`, `preferences_changed`, `preferences_deleted` | отдельной read-модели нет |

`posted` и `thread_updated` могут описывать один reply. Inbox обязан принимать
оба события идемпотентно и отдавать приоритет тредовой проекции.

Часть фактически используемых CRT-полей опережает опубликованную OpenAPI-схему:
официальная server model содержит `before`, `after`, `unread`, root counters и
`total_unread_*`, тогда как не все они перечислены в текущем `users.yaml` и
`definitions.yaml`. Текущий Flutter-клиент уже использует `before` и декодирует
unread totals. Реализация Inbox должна иметь server-version/capability tests и
fallback на документированную page pagination с client-side unread filter, а
не молча считать недокументированные параметры доступными на любом сервере.

### Настройки mentions и keywords

Официальный web-клиент сохраняет настройки в `User.notify_props`:

- `@username` всегда является прямым mention;
- чекбокс username добавляет также plain `username` в `mention_keys`;
- `first_name=true` включает case-sensitive совпадение с именем;
- `mention_keys` — comma-separated custom keywords, сравнение без учета
  регистра;
- `channel=true` включает `@channel`, `@all` и `@here`;
- `@here` считается mention только для подходящего presence в момент отправки;
- group mentions вычисляются сервером по членству пользователя в группе;
- `comments=any|root|never` относится к reply notifications при выключенном
  CRT; при CRT источником служит thread following;
- `channel_mention_auto_follow_threads` и channel-level
  `channel_auto_follow_threads` влияют на автоматическое отслеживание тредов.

На уровне channel member действуют отдельные `notify_props`:

- `desktop` и `push`: `default|all|mention|none`;
- `mark_unread`: `all|mention`; значение `mention` используется для muted
  channel;
- `ignore_channel_mentions`: `default|on|off`;
- `channel_auto_follow_threads`: `on|off`.

Таким образом, mention detection и доставка desktop/push alert — разные
механизмы. Сервер сначала вычисляет получателей mentions и увеличивает
`mention_count`, а затем отдельно применяет transport-specific настройки
desktop/push/email. Inbox не должен интерпретировать наличие push token или
текущий permission ОС как фильтр содержимого очереди.

Для стабильного между устройствами поведения предлагается считать канал
подписанным на все сообщения, если:

```text
member.mark_unread == all
AND (
  effective(member.desktop, user.desktop) == all
  OR effective(member.push, user.push) == all
)
```

`default` наследует user-level значение. Email не участвует: это отложенный
transport без уровня `all|mention`, а не семантика очереди. Mention включается
независимо от этого правила, если он был засчитан сервером. Muted channel
пропускает только прямые/keyword mentions, которые сервер не отфильтровал.

Это решение требует подтверждения продукта: альтернативой является отдельная
Inbox-specific настройка, которая будет понятнее, но перестанет буквально
следовать существующим notification preferences.

### Ограничение исторических mentions

Channel member и `GET /users/{user}/channels/{channel}/unread` возвращают
счетчики, но не post IDs mentions. `GET .../posts/unread` возвращает контент
вокруг старейшего unread без per-user mention reason. WebSocket `posted`
содержит текущий пост и вычисленный сервером список mentions, поэтому realtime
классификация точна.

Официальная функция Recent Mentions также не является полным feed: web-клиент
строит OR-search по mention keys, исключает `@channel`, `@all`, `@here`, а
официальная документация отдельно указывает, что LDAP group mentions не входят
в эту выборку.

Для standard-API MVP на cold start:

1. загрузить весь непрочитанный диапазон candidate channel;
2. применить domain policy, повторяющую серверный parser для username,
   first name, custom keys, channel-wide и доступных current group mentions;
3. пересечь результат с unread диапазоном;
4. сравнить число найденных mentions с `mention_count_root`;
5. при расхождении показать неблокирующее предупреждение о неполной
   реконструкции и предложить refresh/open channel, не выдавая обычные посты за
   гарантированные mentions.

Для полной точности рекомендуется endpoint вида:

```http
GET /plugins/<id>/api/v1/users/me/inbox?since=<timestamp>&cursor=<cursor>
```

возвращающий `post_id`, `root_id`, `channel_id`, `reason` и серверный cursor.
Domain и UI ниже не зависят от наличия этого endpoint: меняется только data
source.

## Продуктовая модель

### Типы элементов New

`ThreadInboxItem`

- ключ: `thread:<rootPostId>`;
- содержит root preview, unread reply/mention counts, last activity и
  участников;
- появляется только при `unread_replies > 0`;
- открывает существующий thread pane/route.

`ChannelPostInboxItem`

- ключ: `post:<postId>`;
- только root post (`root_id` пустой), чтобы reply не дублировал CRT source;
- причина: `directMention`, `keywordMention`, `groupMention`,
  `channelMention` или `allMessagesSubscription`;
- открывает канал с позиционированием на post ID.

`DirectMessageBundleInboxItem`

- ключ UI: `direct:<channelId>:<firstPostId>`;
- хранит непустой ordered list post IDs;
- канал имеет тип `D` или `G`;
- открывает диалог на первом непрочитанном post ID и отмечает канал просмотренным.

System posts (`type` начинается с `system_`), собственные сообщения, удаленные
посты и posts с `silent_notification=true` не создают новые элементы. Удаление
уже показанного поста удаляет его из элемента; пустой элемент исчезает.

### Люди и автоматизации в DM

Внутри каждой вкладки direct communications отображаются двумя визуально
отдельными секциями:

1. `People`;
2. `Bots & integrations`.

Сообщение считается автоматическим, если выполнено хотя бы одно условие:

- автор имеет `User.is_bot=true`;
- post props содержат `from_bot=true`, `from_webhook=true` или
  `from_plugin=true`.

Incoming webhook может использовать display name обычного пользователя,
поэтому одного `is_bot` недостаточно. В GM классификация выполняется по автору
конкретного bundle. Отдельные bundles разных классов не объединяются.

### Группировка DM/GM

Алгоритм детерминирован и применяется после определения queue membership:

1. оставить только входящие non-system, non-silent root posts из `D`/`G`
   channels;
2. сортировать по `create_at`, затем по post ID;
3. объединять только соседние сообщения с одинаковыми `channelId`, `authorId`,
   automation class и queue;
4. продолжать bundle, если разница между соседними `create_at` не больше
   `120000` мс включительно;
5. сообщение другого автора, собственное сообщение, reply, удаленный/system
   post или разница `120001` мс начинает новый bundle.

Правило транзитивно: интервалы 0:00, 1:50 и 3:40 образуют один bundle, потому
что каждый соседний gap не больше двух минут.

При переносе bundle в Postponed сохраняется ссылка на каждый его post. Если
новый DM приходит в пределах двух минут от последнего сообщения еще
существующего postponed bundle, он наследует Postponed и его preference
создается автоматически. Если предыдущий bundle уже разобран или удален,
новое сообщение попадает в New.

### Сортировка и badges

- Обе очереди сортируются по последней активности, новые сверху.
- Для Postponed `added_at` используется только как secondary sort и для
  отображения «отложено тогда-то»; новая активность треда не должна молча
  поднимать отложенный тред, кроме нового mention.
- Badge Inbox показывает количество UI items после дедупликации и DM grouping,
  а не сумму post IDs.
- Thread item считается одной коммуникацией независимо от числа replies.

## Инварианты и дедупликация

Порядок canonicalization:

1. reply превращается в `thread:<rootId>` при наличии CRT thread candidate;
2. root post из `D`/`G` превращается в direct bundle;
3. оставшийся root post превращается в channel item;
4. одинаковый post ID принимается только один раз;
5. Postponed suppression применяется после canonicalization.

Обязательные инварианты:

- `New.postIds INTERSECT Postponed.postIds` пусто;
- `New.threadRootIds INTERSECT Postponed.threadRootIds` пусто;
- reply, поглощенный thread item, не участвует в channel/DM bundle;
- повтор `posted`, повтор страницы REST и пара `posted + thread_updated`
  идемпотентны;
- один thread root существует максимум в одном item;
- direct bundles могут иметь одинакового автора в обеих очередях только при
  разрыве группировки больше двух минут или иной явной границе bundle.

При конфликте источник имеет приоритет:

```text
explicit new mention in postponed thread
  > Postponed preference
  > unread CRT thread
  > direct/group message
  > channel message
```

## Хранение Postponed

### Рекомендуемый формат

Не следует хранить всю очередь одним JSON-массивом в одном preference.
Mattermost ограничивает `Preference.value` 20 000 символами, а API не дает
ETag/compare-and-swap для preference. Read-modify-write одного массива теряет
параллельные add/remove с двух устройств.

Вместо этого category является ключом списка, а один preference — одним
каноническим postponed message:

```json
{
  "user_id": "<current-user-id>",
  "category": "postponed_messages",
  "name": "<canonical-post-id>",
  "value": "{\"v\":1,\"post_id\":\"<canonical-post-id>\",\"added_at\":1788432000000,\"target_post_id\":\"<optional-selected-reply>\",\"kind\":\"post|thread\"}"
}
```

- Для thread `name/post_id` равен root post ID.
- Для обычного channel/DM сообщения он равен post ID.
- `target_post_id` нужен, если пользователь отложил конкретный reply, но
  каноническим объектом остается весь thread.
- `added_at` — UTC Unix milliseconds, выставленные клиентом; server time
  предпочтительнее, если будущий endpoint начнет его возвращать.
- DM bundle записывается несколькими preferences с одинаковым action
  `added_at`.

Чтение выполняется через
`GET /users/{user_id}/preferences/postponed_messages`, гидратация — одним или
несколькими bounded batch `POST /posts/ids`. Недоступный/удаленный post остается
placeholder с действием Remove, пока preference явно не удален.

Добавление выполняется `PUT /users/{user_id}/preferences`. Удаление —
`POST /users/{user_id}/preferences/delete` для точных category/name пар.
Оба endpoint принимают не более 100 preferences за запрос, поэтому большие DM
bundles делятся на bounded batches. WebSocket preference events синхронизируют
очередь между открытыми клиентами.

Это намеренное отклонение от первоначальной идеи «отправить обновленный список
без удаленного»: логически API по-прежнему хранит список по ключу
`postponed_messages`, но физически удаляется один элемент, а не перезаписывается
вся очередь. Такой формат устраняет общий лимит списка и основную
multi-device race.

### Не рекомендуемый совместимый вариант

Если backend contract обязательно требует один список, можно использовать
`category=inbox`, `name=postponed_messages`, `value={v,revision,items:[...]}`.
Тогда необходимы hard cap, read-before-write merge и предупреждение, что
одновременные удаления/добавления остаются last-write-wins. Для production
этот вариант не рекомендуется.

## Переходы состояния и side effects

| Действие | Локальный результат | Серверный side effect |
| --- | --- | --- |
| Open thread из New | item исчезает после успешного read | update thread read до snapshot timestamp |
| Open channel/DM из New | открывается post context; исчезают все New items этого channel до view timestamp | view channel; endpoint отмечает канал целиком прочитанным |
| Postpone channel/DM | item перемещается, unread channel не изменяется | сначала save preferences |
| Postpone thread | thread перемещается и перестает получать обычные replies | save root preference, mark thread read, затем unfollow |
| Remove из Postponed | item/часть bundle удаляется | delete exact preferences; read state не меняется |
| Open из Postponed | открывается context, item остается | обычный read action источника; preference не удаляется |
| Новый explicit mention в postponed thread | preference удаляется, thread появляется в New и снова follows | follow при необходимости, затем delete preference |

У channel read state нет операции «прочитать только один произвольный post».
`view channel` отмечает канал целиком просмотренным. Поэтому открытие одного
New channel/DM item обязано удалить из New все более старые элементы этого же
канала, подтвержденные `last_viewed_at`. Postponed preferences при этом остаются.

Для Postponed выбран explicit completion: простой просмотр не удаляет элемент.
Это предотвращает случайную потерю задачи при навигации; удаление выполняется
действием `Done/Remove`.

### Порядок операций и частичные ошибки

При Postpone preference сохраняется первым. Только после успешной записи UI
подтверждает перенос. Для thread следующие mark-read/unfollow повторяются с
backoff; при ошибке item остается в Postponed и client-side suppression не
допускает дубля в New. После следующего cold start reconciliation завершает
недостающие операции.

При Remove удаление можно показывать оптимистично, но при ошибке preference
возвращается в UI с неблокирующей ошибкой. Discarded futures запрещены; retry
должен иметь централизованный error handler.

## Realtime и восстановление

`InboxRepository` строит атомарный REST snapshot, затем controller применяет
события к этому snapshot:

- `posted`: декодировать post один раз, отбросить self/system/deleted,
  использовать server `mentions` для точной текущей причины, обновить direct
  grouping или channel item;
- `thread_updated`: upsert по root ID и поглотить соответствующий reply;
- `thread_follow_changed`, `thread_read_changed`: обновить/удалить thread item;
- `post_edited`: обновить preview без изменения порядка по `create_at`;
- `post_deleted`: удалить post, пересобрать bundle или показать deleted root
  thread по существующим правилам;
- preference events: upsert/delete postponed reference и повторно применить
  exclusivity;
- изменение current user/channel notify props: пересчитать eligibility или
  запустить refresh.

Каждое событие хранит последний WebSocket `seq`. На gap, reconnect, смене
account/server или resume после длительной паузы event stream считается
недостоверным и запускается полный network-first refresh. Состояние с полезными
данными остается на экране; ошибка refresh показывается неблокирующе.

## REST snapshot

Рекомендуемая последовательность:

1. Параллельно получить current user, teams, channels + memberships,
   `postponed_messages` и unread followed threads по всем teams.
2. Объединить channels/threads по ID; D/GM, возвращенные в нескольких team
   запросах, дедуплицировать.
3. Определить candidate channels по root counters. Для CRT использовать
   `total_msg_count_root - member.msg_count_root`, чтобы replies не дублировали
   thread source. На старом сервере без root counters применить фильтр
   `root_id.isEmpty` после загрузки.
4. С concurrency не больше четырех загрузить unread ranges через
   `GET /users/{user}/channels/{channel}/posts/unread` и при необходимости
   продолжить `GET /channels/{channel}/posts?after=...` до reconciliation со
   счетчиками. Каждый запрос bounded (до 200 для around-unread, стандартные
   страницы по 60 для продолжения).
5. Гидратировать postponed post IDs через `POST /posts/ids`, затем профили
   авторов одним batch lookup.
6. Построить source projections, применить canonicalization, suppression,
   DM grouping и сортировку.
7. Только после атомарной сборки заменить initial state. При initial failure
   показать retry; при refresh failure сохранить старый snapshot.

Все request groups отменяются при закрытии экрана или superseding refresh.
Сообщения, треды, sidebar data и sync cursor не сохраняются в Drift.

## Архитектура реализации

Новый код следует оформить вертикальным срезом:

```text
lib/src/features/inbox/
  domain/
    models/
    policies/
    repositories/inbox_repository.dart
    repositories/postponed_repository.dart
  data/
    dto/
    mappers/
    repositories/mattermost_inbox_repository.dart
    repositories/mattermost_postponed_repository.dart
  presentation/
    controllers/
    widgets/
    inbox_page.dart
```

Domain не знает о Dio, DTO, Riverpod, Flutter или WebSocket package. Он владеет
policy-функциями:

- `resolveNotificationEligibility`;
- `classifyAttentionReason`;
- `canonicalizeInboxCandidates`;
- `groupDirectMessages`;
- `reconcileQueues`.

Data вызывает только расширенный `MattermostApi` и `WebSocketGateway`.
Presentation получает готовые domain items и вызывает repository/use case
actions. Существующие thread pane, message primitives и navigation contracts
переиспользуются через публичные интерфейсы, без импорта presentation/data
internals соседних feature.

### Необходимые API-контракты

В `MattermostApi` потребуются методы для:

- channel memberships пользователя;
- posts around oldest unread и cursor continuation;
- posts by IDs;
- preferences by category, update и delete;
- view channel;
- follow/unfollow thread;
- получения всех team snapshots, а не только первой команды.

DTO необходимо расширить:

- Channel: `total_msg_count_root`;
- ChannelMember: read/unread counters и полные notify props;
- User notify props: `channel_mention_auto_follow_threads` и необходимые
  default fields;
- Post/User: automation markers, которые явным mapper переходят в domain.

`WebSocketGateway` должен отдавать типизированные domain-neutral события,
поддерживать auth/reconnect, sequence tracking, cancellation и не логировать
post body, cookies или authorization data.

## UI

- В sidebar/bottom navigation пункт Threads заменяется на Inbox.
- Внутри Inbox — доступные с клавиатуры tabs `New` и `Postponed`.
- Preview использует текущие thread/message primitives и показывает source:
  channel, thread, DM/GM, human или bot/integration.
- Основные действия доступны мышью, touch и клавиатурой: Open, Postpone,
  Remove/Done.
- Compact layout открывает source route поверх списка; expanded layout может
  использовать существующий side thread pane.
- Выбор layout зависит только от constraints и общих breakpoints.
- Нужны semantics labels, focus restoration, touch targets, light/dark theme,
  large text scale и локализованные строки; строки в widgets не хардкодятся.
- Refresh/loading-more сохраняют существующие cards и scroll position.

## Тестовая стратегия

Domain unit tests:

- все комбинации user/channel notify props;
- case-sensitive first name и case-insensitive username/custom keywords;
- channel-wide/group mention exclusions;
- source precedence и повторные события;
- thread/post exclusivity;
- DM gaps `119999`, `120000`, `120001` мс, transitive grouping и author breaks;
- people/bot/webhook classification;
- postponed thread reactivation на новом mention;
- недоступные/удаленные postponed posts.

Data/API tests:

- точные paths/query/body всех новых endpoints;
- multi-team merge и D/GM deduplication;
- unread pagination completeness;
- preferences batches по 100;
- reconnect и WebSocket sequence gap;
- REST/WS duplicate delivery.

Controller/widget tests:

- initial loading, success, empty, retry;
- refresh/loading-with-data и pagination failure;
- Open/Postpone/Remove partial failures;
- compact/medium/expanded widths по обе стороны breakpoints;
- large text, keyboard traversal, focus restoration и semantics;
- счетчик navigation после grouping/deduplication.

После реализации обязательны format, `flutter analyze`, `dart analyze`,
focused tests и full suite для cross-cutting WebSocket/API изменений.

## Этапы внедрения

1. Добавить DTO/API contracts, preferences repository и WebSocketGateway.
2. Реализовать чистые domain policies и REST-only Inbox за feature flag.
3. Добавить realtime reconciliation и sequence-gap refresh.
4. Добавить Postponed actions и multi-client preference events.
5. Заменить navigation Threads на Inbox после parity-тестов; старый Threads
   route оставить временным rollback path.
6. Отдельно решить, нужен ли серверный exact-attention endpoint до снятия
   feature flag в production.

## Решения, требующие продуктового подтверждения

1. Считать ли `desktop == all OR push == all` подпиской Inbox на все сообщения
   канала. Рекомендация: да, чтобы очередь была одинаковой на всех устройствах.
2. Включать ли GM. Рекомендация: да, как direct conversation, с группировкой по
   конкретному автору.
3. Удалять ли Postponed при открытии. Рекомендация: нет; только явный Done/Remove.
4. Принять ли per-message preferences вместо одного JSON-списка.
   Рекомендация: да, ради multi-device correctness и отсутствия лимита 20 000.
5. Требуется ли 100% точность historical mentions. Если да, server extension
   является обязательным, а не факультативным улучшением.

## Источники

- [Mattermost API v4: users/threads](https://github.com/mattermost/mattermost/blob/master/api/v4/source/users.yaml)
- [Mattermost API v4: channels, members, unread и view](https://github.com/mattermost/mattermost/blob/master/api/v4/source/channels.yaml)
- [Mattermost API v4: posts, posts/unread и posts/ids](https://github.com/mattermost/mattermost/blob/master/api/v4/source/posts.yaml)
- [Mattermost API v4: preferences](https://github.com/mattermost/mattermost/blob/master/api/v4/source/preferences.yaml)
- [Server model: thread counters и pagination options](https://github.com/mattermost/mattermost/blob/master/server/public/model/thread.go)
- [Server model: channel member counters и notify props](https://github.com/mattermost/mattermost/blob/master/server/public/model/channel_member.go)
- [Server model: preference limits](https://github.com/mattermost/mattermost/blob/master/server/public/model/preference.go)
- [Server mention keyword construction](https://github.com/mattermost/mattermost/blob/master/server/channels/app/mention_keywords.go)
- [Server mention parser](https://github.com/mattermost/mattermost/blob/master/server/channels/app/mention_parser_standard.go)
- [Server notification and WebSocket flow](https://github.com/mattermost/mattermost/blob/master/server/channels/app/notification.go)
- [Official web notification settings implementation](https://github.com/mattermost/mattermost/blob/master/webapp/channels/src/components/user_settings/notifications/user_settings_notifications.tsx)
- [Official Recent Mentions implementation](https://github.com/mattermost/mattermost/blob/master/webapp/channels/src/actions/views/rhs.ts)
- [User guide: mentions and keywords](https://docs.mattermost.com/end-user-guide/preferences/manage-your-mentions-keywords-notifications.html)
- [User guide: mention behavior](https://docs.mattermost.com/end-user-guide/collaborate/mention-people.html)
- [User guide: channel-specific notifications](https://docs.mattermost.com/end-user-guide/preferences/manage-your-channel-specific-notifications.html)
- [User guide: thread reply notifications](https://docs.mattermost.com/end-user-guide/preferences/manage-your-thread-reply-notifications.html)
