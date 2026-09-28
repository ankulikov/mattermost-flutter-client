# Источники и условия попадания сообщений в Inbox

Статус: research / product contract  
Дата проверки upstream: 2026-09-26  
Scope: ожидаемое поведение Inbox по официальным server, web и mobile
реализациям Mattermost; без сопоставления с текущей реализацией Flutter-клиента.

## Короткий вывод

Mattermost не предоставляет единый REST endpoint с лентой уведомлений. Inbox
нужно собирать как проекцию нескольких серверных состояний:

- followed threads и их unread counters;
- unread direct/group channels;
- unread channel posts и серверные mention counters;
- пользовательские и channel-level notification preferences.

На новом сообщении сервер авторитетно вычисляет mentions, group membership,
`@here`, получателей DM/GM и состояние followed threads. Затем он отправляет
`posted` всем подходящим участникам канала и персональный `thread_updated`
подписчикам треда. В `posted.data.mentions` находится список пользователей,
которых сервер признал упомянутыми, а в `posted.data.followers` — получатели
desktop-уведомления о followed thread. Официальный web-клиент использует эти
поля и локальные настройки, чтобы решить, показывать ли desktop notification.

REST хранит итоговые unread/mention counters, но не хранит для клиента список
post ID с причиной каждого mention. Поэтому:

- threads, DM/GM и сообщения из каналов с режимом `all` восстанавливаются после
  cold start детерминированно;
- исторические username, group, channel-wide и keyword mentions нельзя
  восстановить абсолютно точно только стандартным API v4;
- realtime-классификация mention точна по `posted.data.mentions`, но конкретную
  причину (`username`, `group`, `@here`, keyword) клиент определяет из текста и
  настроек только после того, как сервер подтвердил сам факт mention.

## Что в этом документе называется уведомлением

Нужно разделять три разных понятия:

1. **Attention event** — сервер посчитал сообщение mention/DM/GM или обновил
   followed thread и соответствующие unread counters.
2. **Inbox item** — in-app элемент, который клиент строит из attention event или
   явно включённого режима «all activity».
3. **Transport notification** — desktop popup, push, email и звук.

Inbox в этом контракте — очередь внимания, а не журнал реально показанных
popup/push-уведомлений. Поэтому разрешение уведомлений в ОС, DND/OOO, активное
окно, открытый канал/тред, `desktop_sound` и доступность push-сервиса не меняют
содержимое Inbox. Они влияют только на transport notification.

Это соответствует разделению в официальной реализации: сервер считает
mentions и unread state, а web-клиент отдельно выполняет
`shouldSkipNotification` перед показом desktop popup.

## Общие условия Inbox

Сообщение или тред может попасть в `New`, только если выполняются общие условия:

- пользователь всё ещё имеет доступ к каналу и сообщению;
- сообщение непрочитано в соответствующей серверной read-модели;
- сообщение создано другим пользователем; собственный обычный post не создаёт
  входящий элемент;
- post не удалён и не имеет `silent_notification=true`;
- служебные posts не создают обычные Inbox items;
- `post_edited` обновляет уже существующий item, но добавленный при редактировании
  mention не создаёт новый item — Mattermost вычисляет уведомления при создании
  post;
- reply при включённых Collapsed Reply Threads относится к thread source и не
  дублируется как channel/DM item;
- повторный REST post, повторный `posted` и пара `posted + thread_updated`
  обрабатываются идемпотентно по post ID/root post ID.

Muted channel — отдельный случай. Mute отключает desktop/push/email и обычную
unread-индикацию, но сервер всё ещё может посчитать прямой username/custom
keyword/group mention. Такой подтверждённый mention остаётся attention event и
может попасть в Inbox. Channel-wide mentions в muted channel по умолчанию
игнорируются сервером. Обычные сообщения muted channel по правилу `all activity`
в Inbox не входят.

## Сводная матрица семи источников

| Источник | Кто определяет принадлежность | Cold start / refresh | Realtime | Настройки, влияющие на источник |
| --- | --- | --- | --- | --- |
| 1. Reply в followed thread | Сервер ведёт membership/following и unread counters | `GET /users/{user_id}/teams/{team_id}/threads?unread=true` | `thread_updated`; content приходит также в `posted`; follow/read меняются через `thread_follow_changed` и `thread_read_changed` | Follow/unfollow, auto-follow, `channel_mention_auto_follow_threads`; checkbox thread notifications влияет на popup, не на unread thread в Inbox |
| 2. DM и GM | Сервер неявно считает входящий DM/GM mention для получателей | Каналы `D`/`G`, membership counters и unread posts | `posted`; `channel_type` различает `D` и `G`, `mentions` содержит серверного получателя | Mute/`none` отключают transport; GM включены в семантику «mentions and direct messages» официального клиента |
| 3. `@username` в канале | Серверный mention parser | Только `mention_count*` плюс posts; точных mention post IDs нет | `posted.data.mentions` — авторитетный признак | `@username` работает всегда; checkbox username добавляет также plain `username` через `mention_keys` |
| 4. `@usergroup` | Сервер раскрывает группу в пользователей и оставляет только участников канала | Только counters + best-effort разбор текста/текущего group membership | `posted.data.mentions` подтверждает получателя; причина group отдельно не передаётся | Allow reference, лицензия/permissions, membership пользователя в группе и канале |
| 5. `@here`, `@channel`, `@all` | Серверный parser с per-user preferences и status | Counters + best-effort; исторический status для `@here` недоступен | `posted.data.mentions` | `notify_props.channel`, channel `ignore_channel_mentions`, mute, server permission и `MaxNotificationsPerChannel`; `@here` mention только для online |
| 6. Обычный channel post при «all activity» | Клиент применяет effective user/channel notification level к серверному unread post | Channel/member snapshot + unread post range | `posted` | effective `desktop` или `push` равен `all`; muted channel исключается |
| 7. Custom keyword | Серверный mention parser | Только counters + best-effort разбор по текущим keys | `posted.data.mentions`; клиент разбирает текст только для label причины | `mention_keys`; keywords case-insensitive; `highlight_keys` не создаёт notification |

Ни `posted`, ни REST snapshot не передают готовое значение вроде
`reason=groupMention`. Для realtime Inbox inclusion нужно доверять наличию
текущего user ID в `mentions`, а локальный parser использовать лишь для
подписи/приоритета причины.

## 1. Сообщения из тредов

### Серверное условие

При включённых CRT сервер поддерживает `ThreadMembership` и `is_following`.
Пользователь автоматически начинает следовать за тредом, если он:

- создал root post;
- ответил в тред;
- был явно упомянут в root/reply;
- включил Follow вручную;
- включил `channel_auto_follow_threads` для канала.

Channel-wide mention также может создать thread membership. Настройка
`channel_mention_auto_follow_threads=false` отключает именно этот auto-follow,
но не само уведомление о `@channel`/`@here`/`@all`.

Inbox item создаётся для followed thread, когда `unread_replies > 0` или
`unread_mentions > 0`. Канонический item один на root post. Reply content из
`posted` сливается в этот item, а не создаёт второй channel/DM item.

### REST и WebSocket

- Snapshot: `GET /users/{user}/teams/{team}/threads?unread=true`.
- Полный тред: `GET /posts/{root_id}/thread`.
- Realtime state: `thread_updated`, `thread_follow_changed`,
  `thread_read_changed`.
- Realtime content: `posted` для самого reply.

`thread_updated` персонализирован сервером: он содержит `UserThread` с
`unread_replies`, `unread_mentions` и предшествующими значениями counters.

### Связь с настройками

Checkbox **Notify me about threads I'm following** соответствует transport
preferences `desktop_threads`/`push_threads` (в старом UI — одному desktop
checkbox). Он решает, показывать ли popup для обычного reply в followed thread.
Он не удаляет сам followed thread и его unread state из Threads/Inbox.

При выключенных CRT действует legacy `notify_props.comments`:

- `any` — replies в тредах, которые пользователь начал или где участвовал;
- `root` — replies только в начатых пользователем тредах;
- `never` — только явный mention.

Для Inbox на CRT-серверах источником истины служит thread membership, а не
`comments`.

## 2. Личные сообщения: DM и GM

### Серверное условие

Для канала типа `D` сервер добавляет получателю `DMMention`. Для типа `G` сервер
добавляет всем остальным участникам `GMMention`. Поэтому DM/GM увеличивают
mention counters даже без `@` в тексте. Начиная с Mattermost v9.1 официальная
семантика notification option включает и group messages, даже если старый label
на скриншоте говорит только «mentions and direct messages».

Inbox включает входящие unread root posts из `D`/`G`. Replies при CRT идут в
thread source. Mute не стирает серверный unread post, но блокирует transport
notifications; по принятой семантике Inbox непрочитанный direct item остаётся
видимым.

### REST и WebSocket

- Snapshot channel metadata: `GET /users/me/teams/{team}/channels`.
- Membership/read counters: `GET /users/me/teams/{team}/channels/members`.
- Unread content: `GET /users/{user}/channels/{channel}/posts/unread` с
  последующей пагинацией до read boundary при необходимости.
- Realtime: `posted`, где `channel_type` равен `D` или `G`.

### Связь с настройками

При global/per-channel `desktop=mention` входящие DM и GM всё равно являются
notification candidates. `desktop=none`, mute, DND и открытый conversation
могут остановить popup, но не меняют принадлежность unread сообщения Inbox.

## 3. Mention по username

### Серверное условие

Сервер всегда добавляет `@<username>` в mention keywords пользователя.
Настройка **Your non case-sensitive username** добавляет ещё и plain username
без `@` в `mention_keys`. Поэтому снятый checkbox не отключает `@username`.

Mention parser работает на сервере по текстовым частям post и поддерживаемого
rich content. Username/custom keys сравниваются без учёта регистра. Сервер не
даёт пользователю упомянуть самого себя обычным post.

### REST и WebSocket

Realtime membership точна: user ID есть в `posted.data.mentions`. В REST
доступен только итоговый `mention_count`/`mention_count_root`; у самого post нет
персонального `mentioned_user_ids` или reason.

## 4. Mention по user group

### Серверное условие

Сервер распознаёт разрешённый group slug, загружает membership группы и
добавляет в mentions только пользователей, которые одновременно:

- состоят в упомянутой группе;
- находятся в нужной team, где это применимо;
- являются участниками канала;
- не являются автором сообщения.

Group mention зависит от лицензии, `allow_reference` группы и permission автора
на group mentions. В DM/GM сервер использует membership самой группы, в обычном
канале — membership группы в team и затем пересечение с channel members.

### REST и WebSocket

В `posted.data.mentions` получатель уже раскрыт сервером до user ID. Group ID или
reason в событии не передаётся. На cold start текущие group membership и текст
дают только приближение: пользователь мог войти/выйти из группы после отправки.

Отдельной пользовательской настройки «не уведомлять по group mention» нет.
Channel mute отключает transport; серверный group mention остаётся mention
counter, если сервер допустил его для этого канала.

## 5. `@here`, `@channel` и `@all`

### Серверное условие

Сервер допускает channel-wide mention только если:

- у автора есть permission `use_channel_mentions`;
- post не является служебной сменой header/purpose;
- число участников меньше server setting `MaxNotificationsPerChannel`;
- у получателя `User.notify_props.channel=true`;
- channel-level `ignore_channel_mentions` не равен `on`;
- для muted channel значение `ignore_channel_mentions=default` также означает
  ignore.

`@channel` и `@all` применяются ко всем подходящим участникам. `@here`
добавляется как mention только online-пользователям в момент отправки. Away или
offline user не получает mention counter задним числом; если у него включено
`all activity`, сообщение всё ещё может попасть по источнику 6.

### REST и WebSocket

Realtime user ID в `posted.data.mentions` является авторитетным. Cold-start
парсинг `@here` принципиально неточен: REST не хранит status пользователя на
момент отправки. Для `@channel`/`@all` также теряются исторические permission,
channel size и старые preferences.

Настройка **Channel-wide mentions** меняет серверный mention result, а не только
popup. Channel-level **Ignore @channel, @here and @all** имеет приоритет для
конкретного канала.

## 6. Сообщения без mention в каналах с «all activity»

Это единственный источник, который не является серверным mention. Сервер
передаёт обычный `posted` и unread counters, а клиент решает, что пользователь
подписался на все сообщения.

Пока отдельной настройки Inbox нет, стабильное между устройствами правило:

```text
include ordinary root post when
  member.mark_unread != mention
  AND (
    effective(member.desktop, user.desktop) == all
    OR effective(member.push, user.push) == all
  )
```

Здесь `default` наследует user-level preference. `mark_unread=mention` означает
mute, поэтому обычные сообщения такого канала исключаются. Replies при CRT не
попадают по этому правилу: их принадлежность определяется followed thread.

На скриншоте global **For all activity** включает этот источник для каналов,
которые не переопределили настройку. **Only for mentions and direct messages**
и **Never** не включают обычные channel posts. Per-channel `desktop=all` или
`push=all` может включить конкретный канал независимо от global default.

REST-восстановление этого источника детерминировано: известны effective setting,
read boundary и посты канала. Realtime строится из `posted`.

## 7. Сообщения по ключевым словам

### Серверное условие

Поле `User.notify_props.mention_keys` — comma-separated список
case-insensitive keywords. Официальный UI сохраняет туда:

- plain username, если включён соответствующий checkbox;
- значения из **Other non case-sensitive words**.

`@username` в это поле добавлять не требуется: сервер проверяет его всегда.
`first_name=true` — отдельный case-sensitive ключ. Custom keywords проходят
тот же серверный parser, что username mentions, и увеличивают mention counters.

`highlight_keys` — другой механизм: он только подсвечивает слова и не создаёт
attention event, Inbox item или transport notification.

### REST и WebSocket

Realtime inclusion подтверждается `posted.data.mentions`; клиент сопоставляет
текст с `mention_keys` только чтобы присвоить reason `keywordMention`. Cold-start
reconstruction неточна при изменении keywords после отправки и обязана
сверяться с server `mention_count`.

## Сопоставление с настройками на скриншотах

| Настройка UI | Wire field | Что меняет в Inbox | Что меняет только в transport |
| --- | --- | --- | --- |
| For all activity | `User.notify_props.desktop=all` | Включает источник 6 для channels с `member.desktop=default` | Разрешает desktop popup для всех подходящих posts |
| Only for mentions and direct messages | `desktop=mention` | Не отключает sources 1–5 и 7; не включает source 6 | Ограничивает popup mentions/DM/GM/followed threads согласно thread setting |
| Never | `desktop=none` | Само по себе не очищает in-app Inbox; source 6 может остаться включён через explicit channel/push `all` | Запрещает desktop popup |
| Notify me about threads I'm following | `desktop_threads=all` вместо `mention` | Не меняет unread followed threads | Разрешает popup для replies без явного mention |
| Notification sound On/Off и выбранный звук | `desktop_sound`, `desktop_notification_sound` | Не влияет | Включает звук и выбирает sound asset |
| Case-sensitive first name | `first_name=true` | Добавляет server mention source 3/7 по имени | Такой mention становится кандидатом popup |
| Non case-sensitive username | plain username в `mention_keys` | Добавляет mention по username без `@`; `@username` всегда активен | Такой mention становится кандидатом popup |
| Channel-wide mentions | `channel=true` | Разрешает source 5 до channel-level/server gates | Такой mention становится кандидатом popup |
| Other non case-sensitive words | custom values в `mention_keys` | Добавляет source 7 | Такой mention становится кандидатом popup |

Дополнительные channel-level настройки, которых нет на скриншотах, но которые
обязательны для корректного результата:

- `desktop`/`push`: `default | all | mention | none`;
- `mark_unread`: `all | mention` (`mention` соответствует mute);
- `ignore_channel_mentions`: `default | on | off`;
- `channel_auto_follow_threads`: `on | off`;
- channel-specific thread notification levels в версиях сервера, где они
  доступны.

## Realtime pipeline

Для каждого `posted`:

1. Декодировать post и `channel_type`.
2. Отбросить deleted/silent/own/system cases согласно общим условиям.
3. Если это reply и есть CRT thread candidate, слить post в
   `thread:<root_id>`; последующий `thread_updated` уточнит counters.
4. Иначе если channel type `D`/`G`, создать direct item.
5. Иначе проверить, содержит ли `mentions` current user ID.
6. Если содержит, принять server mention как авторитетный и локально определить
   наиболее специфичную reason: group > username/first name > custom keyword >
   channel-wide.
7. Если не содержит, применить правило source 6 для ordinary root post.
8. Слить результат по post/root ID и обновлять/удалять его по
   `post_edited`/`post_deleted` без повторного вычисления нового mention.

`thread_updated` и `posted` могут прийти для одного reply в любом порядке.
Клиент не должен создавать два item.

## Cold start, refresh и reconnect

Рекомендуемый snapshot:

1. Получить current user (`notify_props`), teams, channels и собственные channel
   memberships (`notify_props`, counters, `last_viewed_at`).
2. Для каждой team получить unread followed threads через
   `GET /users/{user}/teams/{team}/threads?unread=true`.
3. Выбрать unread `D`/`G` и channels, где есть `mention_count*` либо effective
   all-activity subscription.
4. Получить unread ranges через
   `GET /users/{user}/channels/{channel}/posts/unread` и при необходимости
   допагинировать до границы `last_viewed_at`.
5. Детерминированно восстановить DM/GM и all-activity items.
6. Для channel mentions выполнить best-effort parsing по текущим preferences и
   memberships, затем сверить количество с `mention_count_root`/`mention_count`.
7. Если найденное число не совпало со счётчиком, не выдавать approximation за
   точный результат: сохранить известные realtime items и показать диагностике
   неполноту snapshot/recovery.

После WebSocket sequence gap применяется тот же full snapshot. Нельзя считать,
что повторный parsing текста полностью заменяет потерянные `posted.mentions`.

## Ограничение стандартного API и варианты продукта

Строго точный historical Inbox для sources 3–5 и 7 требует server endpoint или
plugin, который возвращает хотя бы:

```json
{
  "post_id": "...",
  "root_id": "...",
  "channel_id": "...",
  "reason": "username|keyword|group|channel|here",
  "mentioned_at": 0
}
```

Без такого endpoint корректный контракт — точный realtime плюс явно
ограниченный REST recovery. Recent Mentions search не является заменой: это
поиск по текущим словам, он не хранит историческую per-user reason, а официальная
документация отдельно оговаривает неполноту group mentions.

## Upstream references

Исследование выполнено по следующим official sources:

- Server mention construction, implicit DM/GM, thread followers and WebSocket
  payloads: [`notification.go`](https://github.com/mattermost/mattermost/blob/3a1f5f0da1868dd2d67a7b8d91ffd6333357354f/server/channels/app/notification.go).
- Mention keys and `@here`/mute/channel-wide filtering:
  [`mention_keywords.go`](https://github.com/mattermost/mattermost/blob/3a1f5f0da1868dd2d67a7b8d91ffd6333357354f/server/channels/app/mention_keywords.go),
  [`mention_parser_standard.go`](https://github.com/mattermost/mattermost/blob/3a1f5f0da1868dd2d67a7b8d91ffd6333357354f/server/channels/app/mention_parser_standard.go).
- User and channel notification fields:
  [`user.go`](https://github.com/mattermost/mattermost/blob/3a1f5f0da1868dd2d67a7b8d91ffd6333357354f/server/public/model/user.go),
  [`channel_member.go`](https://github.com/mattermost/mattermost/blob/3a1f5f0da1868dd2d67a7b8d91ffd6333357354f/server/public/model/channel_member.go).
- Official web desktop decision tree:
  [`notification_actions.tsx`](https://github.com/mattermost/mattermost/blob/3a1f5f0da1868dd2d67a7b8d91ffd6333357354f/webapp/channels/src/actions/notification_actions.tsx).
- Typed WebSocket contracts for `posted` and thread events:
  [`websocket_messages.ts`](https://github.com/mattermost/mattermost/blob/3a1f5f0da1868dd2d67a7b8d91ffd6333357354f/webapp/platform/client/src/websocket_messages.ts).
- Official mobile handling of `posted` and thread events:
  [`posts.ts`](https://github.com/mattermost/mattermost-mobile/blob/bc03c18f88581bde36dd82a84321b2ddde40d12c/app/actions/websocket/posts.ts),
  [`threads.ts`](https://github.com/mattermost/mattermost-mobile/blob/bc03c18f88581bde36dd82a84321b2ddde40d12c/app/actions/websocket/threads.ts),
  [`threads REST client`](https://github.com/mattermost/mattermost-mobile/blob/bc03c18f88581bde36dd82a84321b2ddde40d12c/app/client/rest/threads.ts).
- API v4 source definitions for
  [users/threads](https://github.com/mattermost/mattermost/blob/3a1f5f0da1868dd2d67a7b8d91ffd6333357354f/api/v4/source/users.yaml),
  [posts/unread](https://github.com/mattermost/mattermost/blob/3a1f5f0da1868dd2d67a7b8d91ffd6333357354f/api/v4/source/posts.yaml) and
  [channels/members](https://github.com/mattermost/mattermost/blob/3a1f5f0da1868dd2d67a7b8d91ffd6333357354f/api/v4/source/channels.yaml).
- Official user documentation:
  [mentions and keywords](https://docs.mattermost.com/end-user-guide/preferences/manage-your-mentions-keywords-notifications),
  [thread reply notifications](https://docs.mattermost.com/end-user-guide/preferences/manage-your-thread-reply-notifications),
  [channel-specific notifications](https://docs.mattermost.com/end-user-guide/preferences/manage-your-channel-specific-notifications),
  [desktop notifications](https://docs.mattermost.com/end-user-guide/preferences/manage-your-desktop-notifications),
  [mentions behavior](https://docs.mattermost.com/end-user-guide/collaborate/mention-people).

Зафиксированные revisions нужны, чтобы последующее изменение upstream не
сделало выводы документа невоспроизводимыми.
