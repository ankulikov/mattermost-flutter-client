# Inbox: контракт, аудит реализации и план доработок

Статус: proposed implementation contract  
Дата: 2026-09-26  
Область: Inbox текущего Flutter-клиента Mattermost  
Основа: [`INBOX_NOTIFICATION_SOURCES.md`](INBOX_NOTIFICATION_SOURCES.md),
[`ARCHITECTURE.md`](ARCHITECTURE.md) и текущий код `lib/src/features/inbox`.

Этот документ заменяет проектные предположения из
[`INBOX_DESIGN.md`](INBOX_DESIGN.md). Старый документ остаётся
историческим draft.

## 1. Резюме решения

Inbox не является серверной лентой. Отдельного endpoint для Inbox
нет и в архитектуре не планируется. Клиент должен сам строить
единую network-first проекцию из стандартных API v4, WebSocket-событий
и user preferences.

Контракт выбора сообщений:

- источником notification-level для Inbox являются только desktop
  notification settings пользователя и канала;
- `push`, `push_threads`, `email` и `email_threads` нигде не участвуют в
  принятии решения о попадании в Inbox;
- replies отслеживаемых CRT-тредов, DM/GM, mentions и обычные
  channel posts поступают как независимые source candidates;
- pure domain policies определяют eligibility, приоритет, дедупликацию,
  группировку и раздел `New`/`Postponed`;
- точный realtime mention определяется по server-provided `mentions`, а не
  только по тексту;
- historical mentions после cold start или WebSocket gap восстанавливаются
  best effort. Неполнота должна быть явно отражена в domain state и UI;
- посты, треды и sync metadata не сохраняются в Drift. На сервере
  хранятся только несекретные Inbox settings и content-free references
  `Postponed`.

## 2. Продуктовый контракт

### 2.1. Очереди

- `New` — текущая волатильная проекция unread communications.
- `Postponed` — серверные references на post/root ID, гидратируемые
  клиентом. Текст сообщения на серве в preferences не дублируется.

Один post/root не может одновременно находиться в обеих очередях.
Новый explicit mention в postponed thread может реактивировать его в `New`,
если это разрешено Inbox settings.

### 2.2. Desktop-only eligibility

Для channel root posts вычисляется:

```text
effectiveDesktop(channel, user) =
  channel.desktop, if channel.desktop is all | mention | none
  user.desktop,    if channel.desktop is default | empty
  mention,         if the inherited value is missing or unknown
```

Консервативный fallback `mention` не даёт неизвестной версии сервера
положить в Inbox всю активность. `mark_unread=mention` используется
только как mute/read gate для ordinary all-activity posts; это не вторая
notification preference.

| Источник | `all` | `mention` | `none` |
| --- | --- | --- | --- |
| Public/private root post | Любой eligible unread root; mute исключает ordinary posts | Только server-confirmed mention | Не включать |
| DM/GM root post | Включать | Включать: Mattermost считает DM/GM direct attention | Не включать |
| Explicit mention в reply | В thread item | В thread item | Не включать |
| Ordinary reply в followed thread | По `desktop_threads` | По `desktop_threads` | Не включать |

Для followed threads используется только `desktop_threads` и
доступный channel-level desktop thread override:

- `all` — любой unread reply отслеживаемого треда;
- `mention` — только `unread_mentions > 0`;
- `none` — тред не попадает в Inbox;
- unknown/empty — консервативный `mention`.

Channel-level `effectiveDesktop=none` является hard gate и для тредов.
Такая модель не обращается к push/email даже как к fallback.

### 2.3. Источники и точность

| Источник | REST snapshot | Realtime | Точность после cold start |
| --- | --- | --- | --- |
| Followed threads | `users/{user}/teams/{team}/threads?unread=true` | `thread_updated`, follow/read events и `posted` content | Точная по counters |
| DM/GM | channels + memberships + unread range | `posted` | Точная |
| Username/keyword mention | mention counters + unread posts | `posted.data.mentions` | Best effort |
| Group/channel-wide/`@here` mention | mention counters + unread posts | `posted.data.mentions` | Best effort; `@here` нельзя точно восстановить |
| Desktop `all` | memberships + unread root range | `posted` | Точная |
| Postponed | preferences + `POST /posts/ids` | preference events | Ссылка точная; content может быть недоступен |

Если на snapshot не удалось сопоставить локально найденные mentions с
`mention_count_root`, snapshot остаётся пригодным, но получает
`completeness=approximateMentions`. UI показывает неблокирующее пояснение.
Клиент не добавляет ordinary posts вместо ненайденных mentions и не
обозначает best-effort result как полный.

### 2.4. Общие фильтры и инварианты

Кандидат не включается, если post создан текущим пользователем,
удалён, служебный, помечен `silent_notification=true` или больше не
доступен пользователю.

Канонические инварианты:

- один post ID принимается один раз, независимо от REST/WS повторов;
- один CRT thread идентифицируется root post ID;
- reply, поглощённый thread item, не дублируется как channel/DM item;
- `post_edited` меняет preview уже известного item, но не добавляет новый
  item и не пересчитывает историческую reason;
- `post_deleted` удаляет post из bundle; пустой bundle исчезает;
- `New.postIds ∩ Postponed.postIds = ∅` и
  `New.threadRootIds ∩ Postponed.threadRootIds = ∅`;
- приоритет: new explicit thread mention, `Postponed`, followed thread,
  DM/GM, channel post;
- результат сортируется по `lastActivityAt` по убыванию, затем по
  стабильному key.

## 3. Что уже реализовано

В клиенте уже есть не прототип, а рабочий вертикальный feature slice:

- domain models для candidates, items, queues, realtime deltas и postponed references;
- pure policies для canonicalization, section classification, DM grouping и
  queue reconciliation;
- `MattermostInboxRepository`, собирающий network-first snapshot по всем
  teams;
- standard API v4 для unread posts, CRT threads, channel read, thread read,
  hydration by IDs и preferences;
- общий `SessionRealtimeService` с reconnect и sequence-gap recovery;
- server-backed `Postponed`: один preference на post/root ID, batch по 100;
- initial loading/error, refresh-with-data, `New`/`Postponed`, sectioned UI,
  mark-read/postpone/remove;
- compact и wide navigation, badge в shell и foreground in-app notification;
- unit, data, controller и widget tests для основных потоков.

Текущий controller живёт на уровне authenticated shell. Это позволяет
обновлять badge и показывать in-app notification, когда вкладка Inbox
закрыта. Сама проекция остаётся в памяти и сбрасывается при logout
или смене account/server. Это нужно явно зафиксировать как исключение
для session-level attention projection, а screen-only состояние вкладок, scroll и
focus сделать auto-disposed.

## 4. Аудит расхождений и необходимые доработки

| Область | Сейчас | Должно быть |
| --- | --- | --- |
| All-activity eligibility | `desktop == all OR push == all` | Только effective `desktop == all`; push/email удалить из policy signature |
| DM/GM eligibility | Все unread DM/GM включаются без desktop gate | Применять effective desktop; `none` исключает conversation |
| Followed threads | Любой thread с `unread_replies > 0`; `desktop_threads` не учитывается | Применить desktop-only thread matrix и включать mention-only case |
| Realtime mentions | Только парсинг `@currentUsername` в тексте | Сначала server `mentions` с current user ID; текст — только reason label |
| Realtime threads | Event names подписаны, но mapper их игнорирует | Upsert/remove/update counters по `thread_updated`, follow/read events; merge reply content |
| Preference/member/user events | Event names подписаны, но mapper их игнорирует | Типизированно обновить scope или запросить bounded refresh |
| `post_edited` | Повторно вычисляет eligibility и может добавить/удалить item | Только заменять preview уже существующего item |
| Snapshot/WS race | WebSocket subscription стартует после REST snapshot | Подписаться и буферизовать события до/во время snapshot, затем атомарно reconcile |
| Unread completeness | `posts/unread` берёт до 200 posts; continuation нет | Дойти до read boundary/counter через bounded pagination с cursor-loop protection |
| Historical mention completeness | Flag в domain уже есть | Показать flag в UI и хранить typed completeness reason, а не bool |
| Postponed sync | REST load/save/delete есть; realtime preference events игнорируются | Синхронизировать между клиентами по preference events |
| Postponed hydration | Недоступная ссылка не показывается | Placeholder с Remove; не удалять server preference молча |
| Postpone thread | Только save preference; mark-read/unfollow оставлены TODO | Durable preference first, затем retryable mark-read/unfollow |
| Reactivation | Domain policy есть, но input `hasNewExplicitMention` не формируется | Follow if needed, delete postponed reference, return thread to `New` |
| DM grouping | Все posts одного author/channel/class объединяются независимо от gap и промежуточных авторов | Зафиксировать bounded consecutive grouping policy и покрыть boundary tests |
| Sections | Ordinary all-activity channel post попадает в `Mentions` | Добавить `All activity` или явно переименовать секцию; recommendation: отдельная секция |
| Navigation | Channel item открывается как thread target | Открывать channel/permalink context; thread pane — только для thread item/reply |
| Localization/accessibility | Строки вынесены в Dart constants, но не локализованы; матрица UI-тестов неполна | ARB/localizations, keyboard/focus, semantics, large text, compact/medium/expanded tests |
| Extensibility | Один repository на ~860 строк смешивает context load, sources, hydration и mapping | Разделить source adapters и projection assembler без дробления network context |

## 5. Целевая клиентская архитектура

### 5.1. Компоненты

```text
presentation
  InboxSessionController       session-scoped projection, badge, realtime
  InboxPageController          auto-disposed tab/filter/scroll/action state
        |
        v
domain
  LoadInbox / ApplyInboxDelta / ExecuteInboxAction
  InboxEligibilityPolicy       desktop-only
  InboxProjectionAssembler     canonicalize -> group -> reconcile -> sort
  InboxCompleteness            exact | approximateMentions | truncated
  InboxRepository + InboxSettingsRepository + PostponedRepository
        ^
        |
data
  InboxContextLoader           user + teams + channels + memberships once
  InboxSnapshotSource[]
    FollowedThreadsSource
    DirectMessagesSource
    MentionedPostsSource
    DesktopAllActivitySource
    PostponedSource
  InboxRealtimeMapper          typed transport event -> domain delta
  MattermostApi / SessionRealtimeService / preferences
```

`InboxContextLoader` один раз собирает shared immutable context. Source adapters не
дублируют запросы channels/members/users. Каждый source возвращает
`InboxSourceResult(candidates, completeness, diagnosticsCodes)`. Diagnostics не
содержат message text, usernames, cookies или tokens.

Новый source добавляется регистрацией adapter и domain precedence, а не
ростом `switch` в UI или прямыми HTTP-вызовами из controller.

### 5.2. Snapshot pipeline

1. Открыть session WebSocket и начать bounded buffering Inbox events.
2. Получить current user, teams, channels и memberships; дедуплицировать
   D/GM, возвращаемые для нескольких teams.
3. Загрузить unread followed threads по всем teams с loop protection.
4. По desktop-only policy выбрать candidate channels.
5. С concurrency не больше 4 загрузить unread root ranges. Если ответ
   ограничен, продолжить до read boundary или явного safety cap.
6. Загрузить postponed references и гидратировать IDs bounded batches.
7. Пакетно получить недостающих авторов и dialog display names.
8. Построить source results и атомарно применить assembler.
9. Проиграть поверх snapshot забуферизованные events по `seq`. При gap
   отбросить новый snapshot и повторить recovery с backoff.
10. Переключиться на live deltas. При refresh до успеха сохранять
    прежнюю полезную проекцию.

### 5.3. Realtime reducer

- `posted` root: проверить server `mentions`, desktop eligibility и common
  filters; upsert по post ID.
- `posted` reply: запомнить content delta для `thread:<rootId>`; не создавать
  channel item.
- `thread_updated`: authoritative unread counters и following; upsert/remove thread.
- `thread_follow_changed`, `thread_read_changed`: точечно изменить membership/read
  или сделать scoped reload одного thread.
- `post_edited`: обновить content только существующего item.
- `post_deleted`: удалить post или root/thread с применением exclusivity.
- `channel_viewed`, `post_unread`: обновить read boundary и reconcile channel.
- channel member/current user/preference changes: пересчитать desktop
  eligibility и `Postponed`.
- `direct_added`, `group_added`: добавить channel в known scope до первого `posted`.

Неизвестное или malformed event изолируется. Если event известен, но его
безопасно нельзя применить локально, reducer запрашивает bounded scoped
refresh. Full snapshot нужен для reconnect, sequence gap, resume и изменений,
затрагивающих весь eligibility context.

## 6. Inbox settings на сервере

### 6.1. Хранение

Отдельный Inbox backend не нужен. Настройки хранятся в Mattermost
user preferences через существующие standard endpoints. Рекомендуемый
namespace — специфичный для клиента, чтобы не конфликтовать с official
clients:

```json
{
  "user_id": "<current-user-id>",
  "category": "mattermost_flutter_inbox",
  "name": "settings",
  "value": "{\"v\":1,\"enabled\":true,\"sources\":{...},\"postponed\":{...},\"presentation\":{...}}"
}
```

Запись мала и изменяется целиком; last-write-wins для одной
пользовательской settings-записи приемлем. Parser обязан:

- проверять `v` и enum values;
- игнорировать unknown fields для forward compatibility;
- при malformed/unknown version возвращать safe defaults, не ломать Inbox;
- не хранить post text, usernames, channel names, tokens и другие персональные
  данные.

Существующую категорию `postponed_messages` следует сохранить без
миграции: один preference на post/root ID лучше защищает от
multi-device races, чем общий JSON-список.

### 6.2. Возможные настройки

| Настройка | Default | Назначение | Рекомендация |
| --- | --- | --- | --- |
| `enabled` | `true` | Включить session projection, badge и UI | В v1 |
| `sources.direct_messages` | `true` | Показывать DM | В v1 |
| `sources.group_messages` | `true` | Показывать GM | В v1 |
| `sources.mentions` | `true` | Username, keyword, group, channel-wide mentions | В v1 |
| `sources.followed_threads` | `true` | Показывать eligible CRT threads | В v1 |
| `sources.all_activity` | `true` | Показывать ordinary posts при desktop `all` | В v1 |
| `sources.automations` | `include` | `include | exclude | separate` для bots/webhooks/plugins | `separate` как UI default; не менять eligibility до product decision |
| `direct_grouping.mode` | `conversation` | `none | consecutive | conversation` | После UX-подтверждения; v1 зафиксировать одну policy |
| `direct_grouping.window_seconds` | `120` | Окно для `consecutive` | Не разрешать неограниченные значения |
| `postponed.reactivate_on_mention` | `true` | Вернуть thread в `New` по explicit mention | В v1 |
| `postponed.remove_on_open` | `false` | Считать ли просмотр completion | Оставить `false`; completion явный |
| `presentation.section_order` | fixed default | Порядок секций | Можно позже; это только UI preference |
| `presentation.muted_sections` | `[]` | Скрыть секцию без изменения unread | Можно позже; UI должен явно показать active filter |

Inbox settings применяются после desktop eligibility. Они могут
сузить Inbox, но не могут расширить `desktop=none` или превратить
`desktop=mention` в `all`. Это оставляет desktop settings основным
серверным контрактом.

Если позже понадобятся per-channel Inbox filters, их следует хранить
по одному preference на channel ID в отдельной категории, а не в
растущем JSON-словаре. Default обязан быть `inherit`; расширение
за пределы desktop eligibility не допускается.

## 7. План задач

Задачи ниже разбиты так, чтобы каждая имела один проверяемый
результат. P0 блокирует production contract; P1 нужен для корректного
MVP; P2 завершает multi-device UX и hardening.

### Этап A. Контракт и domain (P0)

| ID | Задача | Acceptance criteria |
| --- | --- | --- |
| INB-001 | Зафиксировать desktop-only eligibility | Ни одна Inbox policy не принимает push/email; есть user/channel/thread matrix tests |
| INB-002 | Заменить wire strings typed domain values | Unknown/default обрабатываются явно; domain не знает DTO |
| INB-003 | Ввести `InboxCompleteness` и source diagnostics | Exact, approximate mentions и truncated snapshot различаются без message content в diagnostics |
| INB-004 | Разделить context loader, source adapters и assembler | Existing behavior покрыт characterization tests; sources не дублируют shared REST calls |
| INB-005 | Разделить session projection и screen state | Badge/realtime живут в auth session; tabs/scroll/focus освобождаются со страницей |

### Этап B. Корректный REST snapshot (P0/P1)

| ID | Задача | Acceptance criteria |
| --- | --- | --- |
| INB-101 | Применить desktop-only policy к channels, DM/GM и threads | `desktop=none` исключает source; `mention`/`all` работают по матрице |
| INB-102 | Дополнить unread ranges до boundary | Нет молчаливой обрезки на 200; есть concurrency cap, cursor-loop guard и typed truncation |
| INB-103 | Уточнить historical mention reconstruction | Username/first name/keywords/channel-wide parsed best effort; mismatch counters даёт approximate state; group/`@here` не заявлены как exact |
| INB-104 | Исправить followed-thread selection | `desktop_threads=all|mention|none`, unread replies/mentions и deleted roots покрыты tests |
| INB-105 | Добавить unavailable postponed placeholder | Reference не теряется; UI даёт Remove; inaccessible content не утекает |
| INB-106 | Отмена и bounded failures | Superseded refresh отменяет Dio work; rate limits и partial source failures не заменяют useful snapshot loader-ом |

### Этап C. Realtime без потерь (P0/P1)

| ID | Задача | Acceptance criteria |
| --- | --- | --- |
| INB-201 | Буферизовать events во время initial/refresh snapshot | Post между REST start/end не теряется; buffer bounded; gap запускает recovery |
| INB-202 | Типизировать Inbox WS payloads | `mentions`, `followers`, `channel_type`, thread/read/follow/preference payloads декодируются толерантно |
| INB-203 | Реализовать root post reducer | DM/GM, exact mentions и desktop `all` upsert идемпотентны; unknown channel не теряется |
| INB-204 | Реализовать thread reducer | `posted + thread_updated` в любом порядке дают один thread item; read/unfollow удаляют его |
| INB-205 | Разделить create/edit/delete deltas | Edit не меняет membership/reason; delete сжимает bundle; duplicates не дают popup |
| INB-206 | Обработать eligibility-context и preference events | Desktop changes и cross-device Postponed попадают в projection без перезапуска |
| INB-207 | Проверить reconnect/gap/resume state machine | Один coalesced refresh, backoff+jitter, old data сохраняются, повторные gaps не создают refresh storm |

### Этап D. Settings и Postponed actions (P1/P2)

| ID | Задача | Acceptance criteria |
| --- | --- | --- |
| INB-301 | Добавить `InboxSettingsRepository` на preferences | Versioned parser, safe defaults, unknown-field preservation strategy, API/batch tests |
| INB-302 | Сделать Postpone thread завершённым workflow | Save reference → mark read → unfollow; после save failure item не двигается; side-effect failures retryable |
| INB-303 | Реализовать explicit-mention reactivation | Follow if needed → remove preference → `New`; repeats idempotent; setting can disable behavior |
| INB-304 | Определить partial batch semantics | Частичный save/delete >100 references не приводит к молчаливой потере; refresh reconciles server truth |
| INB-305 | Добавить settings UI | Меняет только Inbox preferences; desktop settings показаны как authoritative, но не дублируются |

### Этап E. UI и navigation (P1/P2)

| ID | Задача | Acceptance criteria |
| --- | --- | --- |
| INB-401 | Исправить секции и DM grouping | Ordinary posts не названы Mentions; grouping bounded и детерминирован; counts совпадают с rendered messages |
| INB-402 | Перевести channel item на channel/permalink navigation | Compact/wide Back возвращает в Inbox со scroll/focus; replies открывают thread |
| INB-403 | Показать completeness и scoped errors | Approximate/truncated state видим, refresh failure не убирает data, retry адресует нужный scope |
| INB-404 | Локализовать Inbox и завершить accessibility | Нет hardcoded user strings; keyboard/focus/semantics/touch targets; light/dark и large text verified |
| INB-405 | Отделить one-shot in-app notifications от state | Event consumed once; refresh/edit/duplicate не показывают stale Snackbar; приватный preview имеет product setting |

### Этап F. Проверка и rollout (P0–P2)

| ID | Задача | Acceptance criteria |
| --- | --- | --- |
| INB-501 | Domain matrix tests | Все desktop user/channel/thread combinations, mute, sources, precedence, edit/delete и queue exclusivity |
| INB-502 | Data/API tests | Multi-team merge, unread continuation, batches, malformed payloads, current user in `mentions`, thread/preference events |
| INB-503 | Controller race tests | Initial load + WS, refresh + deltas, action + delta, cancel/logout/account switch, reconnect storms |
| INB-504 | Widget/navigation tests | Initial/error/with-data refresh, five sections, compact/medium/expanded, breakpoint edges, large text, keyboard, semantics |
| INB-505 | Security/performance pass | В logs нет auth/cookies/message contents; bounded concurrency/buffers/batches; large JSON не блокирует UI isolate |
| INB-506 | Documentation and release gate | Обновлён `ARCHITECTURE.md`; format, `flutter analyze`, `dart analyze`, focused + full tests проходят |

## 8. Порядок внедрения

1. INB-001–INB-004: зафиксировать semantics и разрезать monolithic
   repository под characterization tests.
2. INB-101–INB-106: сделать cold start и refresh предсказуемыми и
   явно показывать границы точности.
3. INB-201–INB-207: закрыть потери между REST и WS, затем добавить
   thread/preferences realtime.
4. INB-301–INB-305: завершить server-backed settings и Postponed workflows.
5. INB-401–INB-405: исправить presentation semantics и navigation после
   стабилизации domain item identity.
6. INB-501–INB-506: полная матрица перед production rollout.

Минимальный production gate: desktop-only policy, exact realtime `mentions`,
thread realtime, WS/snapshot buffering, unread completeness, visible completeness state,
Postponed thread workflow и тесты P0/P1. Наличие экрана Inbox без этих
пунктов не означает production completeness.

## 9. Осознанные ограничения

- Строго точный historical Inbox для username/group/channel-wide/keyword
  mentions недостижим после потери realtime context только стандартным
  API v4. Это product limitation, а не временный TODO на server endpoint.
- Клиент не подменяет неизвестные mentions обычными posts и не
  скрывает approximate state.
- После safety cap snapshot может быть `truncated`; cap не может молча
  выдавать результат за полный.
- Inbox settings не меняют Mattermost read state сами по себе.
- Отключение source скрывает его из Inbox, но не помечает underlying posts
  прочитанными.
- Любое будущее расширение добавляется как новый client-side source
  adapter или policy, а не как зависимость от несуществующего Inbox endpoint.
