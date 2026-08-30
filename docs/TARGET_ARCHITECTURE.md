# Целевая архитектура Mattermost Flutter

Статус: целевое видение и план миграции. Этот документ не описывает уже
завершённый рефакторинг.

## 1. Резюме решения

Текущая вертикальная структура `features/<feature>/{domain,data,presentation}`
формально соблюдает направление зависимостей внутри одной feature, но плохо
соответствует фактической предметной модели клиента. Посты, треды, вложения,
реакции, emoji и пользователи участвуют в одних и тех же сценариях. В результате
одна feature начинает использовать модели, репозитории, провайдеры и UI другой
feature.

Целевая структура состоит из трёх продуктовых слоёв:

```text
ui  ───────────────► domain ◄────────────── data
│                         ▲                   │
└── вызывает domain-      └── возвращает ────┘
    контракты через
    repository providers
```

- `data` владеет Mattermost API, DTO, БД, кешами, platform storage, реализациями
  репозиториев и их Riverpod wiring;
- `domain` владеет общими бизнес-сущностями, чистыми правилами и контрактами
  репозиториев;
- `ui` владеет controller/view-model, состоянием отображения и widgets. Feature
  в этом слое означает только UI-сценарий, а не владельца данных;
- `ui/core` содержит только переиспользуемые элементы без бизнес-смысла;
- на один domain aggregate существует один публичный репозиторий. Внутренние
  API services, DAO, cache и mapper не становятся дополнительными публичными
  репозиториями той же сущности.

Это не только перемещение файлов. Во время миграции необходимо убрать
принадлежность общих моделей конкретным feature, перенести data-политику из UI,
сделать кеш пользователей частью `UserRepository` и разорвать зависимость
активного API от presentation-state авторизации.

## 2. Текущее состояние

### 2.1. Структура

Сейчас код организован следующим образом:

```text
lib/src/
├── app/
│   └── di/app_providers.dart
├── core/
│   ├── api/                 # MattermostApi, Dio, все DTO одним файлом
│   ├── async/
│   ├── database/            # Drift и cached_user_profiles
│   ├── logging/
│   ├── storage/
│   ├── sync/
│   ├── ui/
│   └── utils/
└── features/
    ├── attachments/{data,domain,presentation}
    ├── auth/{data,domain,presentation}
    ├── bootstrap/presentation
    ├── channels/{data,domain,presentation}
    ├── emojis/{data,domain}
    ├── messages/{data,domain,presentation}
    ├── posts/{data,domain,presentation}
    ├── threads/{data,domain,presentation}
    └── users/{data,domain,presentation}
```

`app/di/app_providers.dart` является единым composition root, но знает обо всех
DTO, data implementations, domain-контрактах, controllers и UI helpers. UI
виджеты большинства feature импортируют этот файл напрямую.

Граф repository providers при этом почти плоский: channel, post и thread
repositories получают общий `MattermostApi` и сами вызывают users endpoints,
вместо зависимости от единого `UserRepository`. Повторное использование data
policy достигается глобальным API decorator, а не композицией entity
repositories через `ref`.

### 2.2. Фактическая связанность

Главная проблема — не сам факт переиспользования, а неправильный владелец
переиспользуемого типа. Например:

- `ChannelPost`, `PostAuthor`, `PostReaction` и `PostAttachment` объявлены в
  `features/messages/domain`, но используются `posts`, `threads` и
  `attachments`;
- `CustomEmojiReference` объявлен в `features/emojis/domain` и встроен в модель
  сообщения;
- `AuthSession` присутствует в контрактах и controllers каналов, сообщений,
  постов и тредов;
- `resolveUserDisplayName` из `features/users/domain` используется mapper-ами
  каналов, сообщений и тредов;
- presentation постов напрямую собирает UI из `channels`, `messages`,
  `attachments` и `threads`; presentation тредов — из `channels`, `messages` и
  `attachments`;
- `bootstrap` импортирует presentation и domain нескольких feature и вручную
  координирует выбор канала и Threads destination.

Наиболее нагруженные направления межfeature-импортов сейчас —
`threads -> messages` и `posts -> messages`. Это показывает, что `messages`
фактически уже является общим слоем, но физически и семантически остаётся
feature.

При этом важные базовые ограничения уже соблюдаются:

- domain не импортирует Flutter, Riverpod, Dio, Drift и API DTO;
- presentation не импортирует Dio, Drift, `MattermostApi` и data
  implementations напрямую;
- REST-вызовы проходят через `MattermostApi`;
- DTO явно преобразуются в domain entities;
- токен хранится в secure storage, а не в UI или Drift.

Эти свойства нужно сохранить при миграции.

### 2.3. Где сейчас проходит неверная граница

#### Общий API декорируется feature-кешем

`activeMattermostApiProvider` оборачивает raw API в `CachedUserProfileApi`.
Декоратор реализует весь `MattermostApi`, но меняет поведение только
`getUsersByIds` и `getUsersByUsernames`, делегируя десятки остальных методов.
Из-за этого:

- user cache не принадлежит `UserRepository`, а неявно меняет общий API;
- любой репозиторий, вызывающий users endpoint, случайно получает cache
  policy;
- БД-строка сначала превращается обратно в DTO, а затем в domain-модель;
- fresh profile и cached profile различаются не контрактом репозитория, а
  выбором конкретного метода API;
- добавление нового метода в `MattermostApi` требует обновлять кеширующий
  декоратор, даже если метод не связан с пользователями.

#### Domain содержит presentation-state

`ChannelSidebarSnapshot` одновременно содержит данные сайдбара и флаги
`isRefreshing`/`refreshFailed`. Эти флаги описывают состояние отрисовки и должны
принадлежать `ChannelSidebarViewState`, а не domain.

Обратная ситуация есть в `ChannelPostsController` и `ThreadController`: вместе
с корректными UI-флагами они владеют правилами объединения страниц,
дедупликацией, reply summary reconciliation, изменением счётчиков треда и
optimistic reaction rollback. Чистые правила сущностей должны быть общими в
domain, а сетевые и cache/pagination решения — в data. Controller должен только
применять результат к view-state.

#### Репозитории нарезаны по операциям и экранам

Одна сущность поста сейчас обслуживается `ChannelPostRepository`,
`MessageSender`, `ReactionRepository`, `ThreadRepository` и частично
`FollowedThreadsRepository`. Пользователь обслуживается отдельными profile,
mention и avatar repositories. Такая нарезка создаёт много публичных контрактов
и вынуждает UI-controller собирать одну операцию из нескольких источников.

Целевое правило — один публичный repository на aggregate, а не один repository
на endpoint, кнопку или экран.

#### Активный data context зависит от UI-состояния

Создание `activeMattermostApiProvider` зависит от `authSessionProvider`, который
является projection состояния `AuthController`. В целевой схеме активная сессия
и API client должны быть data-owned context; UI наблюдает domain-проекцию этой
сессии, а не участвует в создании data dependencies.

#### Composition logic смешана с UI-командами

Глобальная функция `openDirectMessage(WidgetRef, UserProfile)` одновременно
вызывает repository, переключает UI destination, выбирает канал и обновляет
сайдбар. Открытие direct channel — data operation. Выбор destination и refresh
видимого sidebar — UI orchestration. Их нужно разделить явной границей команды
controller-а.

## 3. Как реализованы существующие сценарии

Этот раздел фиксирует поведение, которое нельзя потерять при реорганизации.

### 3.1. Авторизация

Текущий поток поддерживает восстановление сессии, ручной session token и SSO.
`AuthController` хранит фазу экрана и координирует server discovery, browser
gateway, проверку токена и отмену устаревшей попытки. Секрет не попадает в
`AuthState`.

`MattermostAuthRepository`:

1. создаёт отдельный Dio-backed client для server URL и transient token;
2. проверяет токен через `GET /users/me`;
3. только после успешной проверки сохраняет credentials в secure storage;
4. активирует один API client текущего аккаунта;
5. закрывает предыдущий transport при смене сервера или logout;
6. при restore удаляет credentials только для повреждённого состояния или
   подтверждённых `401/403`, но сохраняет их при network/server failure.

Нативный SSO получает `MMAUTHTOKEN` через platform cookie manager. Web явно
возвращает browser-unavailable. Диагностические логи редактируют token, cookie,
query values и персональные данные.

Целевая реализация сохраняет это поведение, но полный auth workflow становится
операцией `AuthRepository`, использующей internal public-config API, browser
service и credential store. UI-controller управляет только фазами и событиями
экрана.

### 3.2. Кеш деталей пользователя

Сейчас Drift-таблица `cached_user_profiles` хранит account-scoped projection
профиля и TTL семь дней. Batch lookup по ID и username выполняется DB-first;
missing и expired записи загружаются batch-запросами. Stale данные не выдаются
после неудачного refresh. Полная карточка пользователя намеренно обходит этот
кеш и параллельно вызывает fresh user endpoint и status endpoint.

Avatar bytes хранятся отдельно во временном `flutter_cache_manager` cache.
Versioned key включает account/server, user ID и picture update timestamp;
одновременные misses объединяются in-flight map. В Drift bytes не сохраняются.

Mention resolution использует username lookup того же кешированного API, а UI
показывает обычный текст при неизвестном пользователе или ошибке.

В целевой схеме всё это принадлежит одному `UserRepository`:

- `getUsers(ids, freshness: cached)` — batch DB-first policy;
- `getUserByUsername`/`resolveUsersByUsernames` — indexed cached lookup;
- `getProfile(id, freshness: fresh)` — профиль плюс presence без batch cache;
- `loadAvatar` — временный versioned byte cache.

`CachedUserProfileApi` удаляется. DAO возвращает cache record, mapper сразу
строит domain `UserSummary`/`UserProfile`, а raw API всегда остаётся raw.

### 3.3. Сайдбар каналов и direct messages

`ApiChannelSidebarRepository` загружает первую команду, каналы и категории.
Каналы и категории запрашиваются параллельно. Имена direct/group dialogs
дополняются users endpoints; ошибка enrichment не блокирует навигацию.
Результат хранится в памяти controller-а. Refresh сохраняет старые данные и
показывает неблокирующую ошибку.

Mapper также содержит fallback category names (`Channels`, `Direct messages`,
`Favorites`). Это user-facing строки внутри data и при миграции они должны
стать semantic category kind в domain, а локализованное имя — задачей UI.

Создание direct channel вызывается отдельным repository и после успеха вручную
меняет selection-state и инициирует sidebar refresh.

В целевой схеме `ChannelRepository` владеет загрузкой navigation snapshot и
созданием/получением direct channel. Для user enrichment его provider получает
`UserRepository` через `ref`. View-state отдельно хранит loading, refreshing,
selection и error presentation.

### 3.4. Лента постов

Лента network-first и живёт только в auto-disposed состоянии открытого канала.
Repository загружает страницу по 60 элементов, сохраняет raw cursor из
`PostList.order`, batch-запрашивает авторов, маппит DTO, отделяет replies и
собирает observed reply summary. Root posts сортируются по `create_at`, затем
по ID.

`ChannelPostsController`:

- показывает initial retry state;
- сохраняет уже показанные посты при ошибке older-page;
- объединяет страницы по post ID;
- объединяет observed reply IDs между страницами;
- отправляет сообщение и сразу вставляет server-authoritative ответ;
- оптимистично переключает reaction и откатывает только её при ошибке;
- принимает отправленный из thread pane reply и обновляет summary root post.

В целевой схеме `PostRepository` владеет channel page, созданием поста и
reaction commands. Raw cursor, author resolution и DTO mapping остаются в data.
Общая детерминированная политика merge/reply-summary находится в domain и
одинаково используется UI-state и будущим realtime reconciliation. Controller
владеет только текущим снимком экрана, loading/error flags и моментом применения
optimistic projection.

### 3.5. Треды

Открытый тред загружается network-first целиком. Repository идёт по
`next_post_id` с `fromPost/fromCreateAt` до `has_next=false`, защищается от
зацикленного cursor, batch-запрашивает авторов и только после полной загрузки
возвращает root и replies. Удалённый reply сохраняет позицию как placeholder.

Followed Threads загружаются отдельным endpoint по 60 элементов. Response уже
содержит roots, counters и participants; отсутствующие root authors
дозагружаются одним batch lookup. Открытие unread thread отмечает read timestamp,
зафиксированный перед первой страницей, только после отображения полного треда.

Сейчас `ThreadController` повторяет reaction logic и часть merge logic постов,
а `FollowedThreadsController` отдельно объединяет страницы и корректирует
unread totals.

В целевой схеме один `ThreadRepository` владеет detail, followed list и mark-read
operations. Общие `Post`/`Reaction` модели находятся в root domain. UI треда
использует общие message widgets, но имеет собственный view-state для scroll
anchor, unread divider, refresh и mark-read feedback.

### 3.6. Вложения, custom emoji и message rendering

Attachment и emoji bytes загружаются авторизованно через API и временные кеши;
credentials в widgets не передаются. Custom emoji использует metadata-first
lookup и fallback по имени. Attachment download делегируется platform file
saver.

`MattermostMarkdown`, avatar, author row, reactions и attachment surfaces
являются переиспользуемым UI сообщения, но не базовыми UI primitives. Поэтому в
целевой структуре они находятся в `ui/messages`, а не в `ui/core`.

WebSocket gateway пока не реализован: собственные POST/reply добавляются из REST
response, события других пользователей realtime не поступают. Целевая структура
резервирует raw realtime service в data; reconciliation идёт через те же
domain-политики, что pagination и optimistic update.

## 4. Целевая структура проекта

```text
lib/
├── main.dart
└── src/
    ├── app/
    │   ├── app.dart
    │   ├── router.dart
    │   ├── bootstrap.dart
    │   └── localization/
    │
    ├── data/
    │   ├── api/
    │   │   ├── mattermost_api.dart              # raw REST contract
    │   │   ├── dio_mattermost_api.dart          # HTTP implementation
    │   │   ├── mattermost_client_factory.dart
    │   │   ├── public_server_api.dart            # unauthenticated config
    │   │   └── dto/
    │   │       ├── user_dto.dart
    │   │       ├── team_dto.dart
    │   │       ├── channel_dto.dart
    │   │       ├── post_dto.dart
    │   │       ├── thread_dto.dart
    │   │       ├── emoji_dto.dart
    │   │       └── file_dto.dart
    │   ├── database/
    │   │   ├── app_database.dart
    │   │   ├── migrations/
    │   │   ├── tables/cached_user_profiles.dart
    │   │   └── daos/user_profile_cache_dao.dart
    │   ├── cache/
    │   │   ├── avatar_cache.dart
    │   │   └── custom_emoji_cache.dart
    │   ├── storage/
    │   │   └── secure_credential_store.dart
    │   ├── platform/
    │   │   ├── sso_browser_service.dart
    │   │   └── attachment_file_saver.dart
    │   ├── realtime/
    │   │   └── mattermost_websocket_gateway.dart
    │   ├── mappers/
    │   │   ├── user_mapper.dart
    │   │   ├── channel_mapper.dart
    │   │   └── post_mapper.dart
    │   ├── repositories/
    │   │   ├── mattermost_auth_repository.dart
    │   │   ├── mattermost_user_repository.dart
    │   │   ├── mattermost_channel_repository.dart
    │   │   ├── mattermost_post_repository.dart
    │   │   ├── mattermost_thread_repository.dart
    │   │   ├── mattermost_emoji_repository.dart
    │   │   └── mattermost_attachment_repository.dart
    │   └── providers/
    │       ├── infrastructure_providers.dart
    │       ├── session_providers.dart
    │       └── repository_providers.dart
    │
    ├── domain/
    │   ├── models/
    │   │   ├── auth_session.dart
    │   │   ├── user.dart                         # summary/profile/presence
    │   │   ├── team.dart
    │   │   ├── channel.dart
    │   │   ├── post.dart                         # author/reaction/attachment refs
    │   │   ├── thread.dart
    │   │   ├── emoji.dart
    │   │   ├── attachment.dart
    │   │   └── page.dart                         # opaque pagination result
    │   ├── repositories/
    │   │   ├── auth_repository.dart
    │   │   ├── user_repository.dart
    │   │   ├── channel_repository.dart
    │   │   ├── post_repository.dart
    │   │   ├── thread_repository.dart
    │   │   ├── emoji_repository.dart
    │   │   └── attachment_repository.dart
    │   ├── policies/
    │   │   ├── user_display_name.dart
    │   │   ├── post_collection.dart
    │   │   └── reaction_projection.dart
    │   └── use_cases/                            # только cross-repository logic
    │
    └── ui/
        ├── core/
        │   ├── theme/
        │   ├── layout/
        │   ├── widgets/                          # без business models/providers
        │   └── localization/
        ├── shell/
        │   ├── shell_page.dart
        │   ├── shell_controller.dart
        │   └── shell_state.dart
        ├── auth/
        │   ├── auth_controller.dart
        │   ├── auth_state.dart
        │   └── widgets/
        ├── channels/
        │   ├── channel_sidebar_controller.dart
        │   ├── channel_sidebar_state.dart
        │   └── widgets/
        ├── posts/
        │   ├── channel_posts_controller.dart
        │   ├── channel_posts_state.dart
        │   └── widgets/
        ├── threads/
        │   ├── thread_controller.dart
        │   ├── followed_threads_controller.dart
        │   └── widgets/
        ├── users/
        │   ├── user_profile_controller.dart
        │   └── widgets/
        └── messages/
            ├── view_models/
            └── widgets/                          # Markdown, author, avatar,
                                                  # reactions, attachments, composer
```

Физическая разбивка DTO и models может уточняться по мере роста. Важны владельцы
и разрешённые зависимости, а не обязательное правило «один класс — один файл».

## 5. Правила зависимостей

### 5.1. Разрешённые импорты

| Откуда | Можно импортировать | Нельзя импортировать |
|---|---|---|
| `domain` | Dart SDK, другие части `domain` | Flutter, Riverpod, Dio, Drift, DTO, `data`, `ui` |
| `data/api` | DTO, HTTP implementation helpers | domain entities, repositories, UI |
| `data/repositories` | raw API, DTO mappers, DAO/cache/platform services, `domain` | UI controllers/widgets |
| `data/providers` | data implementations, domain repository contracts, другие data providers | UI state/providers |
| `ui` | domain models/contracts, repository providers, `ui/core`, public UI widgets | raw API, DTO, Dio, DAO, cache/storage implementation |
| `ui/core` | Flutter и generic design tokens | Mattermost domain models, repository providers, feature controllers |
| `app` | public UI entry points, provider bootstrap, router/theme | endpoint/data policy |

Ни одна UI-папка не владеет domain entity. UI-specific view-model допустима,
если она является projection domain data для конкретного экрана и не начинает
использоваться другими UI-feature как бизнес-модель.

### 5.2. Raw API

`MattermostApi` — stateless transport boundary:

- принимает request DTO/scalars и возвращает response DTO;
- не знает о domain models, Riverpod, Drift, TTL, UI-state и navigation;
- не кеширует и не обогащает данные;
- не выбирает freshness policy;
- является единственным местом REST-взаимодействия, а Dio существует только в
  его implementation/factory;
- public server discovery может быть отдельным raw client, потому что работает
  до появления authenticated account context;
- WebSocket — отдельный raw `WebSocketGateway`, не метод repository и не widget
  service.

### 5.3. Репозитории

Контракт repository находится в `domain/repositories`, чтобы UI зависел от
абстракции и domain types. Реализация и вся data policy находятся в
`data/repositories`.

Один repository соответствует aggregate:

| Repository | Ответственность |
|---|---|
| `AuthRepository` | restore/login/SSO/logout, secure credentials, active account lifecycle |
| `UserRepository` | cached summaries, fresh profile/presence, username resolution, avatar content |
| `ChannelRepository` | team/channel navigation snapshot, categories, direct/group channel operations |
| `PostRepository` | channel pages, create post/reply, reactions, post reconciliation input |
| `ThreadRepository` | full thread, followed threads, mark read/follow state |
| `EmojiRepository` | metadata and temporary image cache |
| `AttachmentRepository` | authenticated content and platform download |

Не следует автоматически создавать `MessageSenderRepository`,
`ReactionRepository`, `MentionRepository` и `AvatarRepository`: это операции
`PostRepository` или `UserRepository`. Если implementation становится большой,
его можно разделить на private services/data sources, не расширяя публичную
поверхность для UI.

«Один repository на сущность» означает единый источник правил aggregate, а не
god object. Если две части имеют независимый lifecycle и consistency boundary,
они могут быть разными aggregates — например, `PostRepository` и
`ThreadRepository`.

### 5.4. Data providers и `ref`

Riverpod wiring располагается в `data/providers`. Providers могут зависеть друг
от друга через `ref`, как требуется целевой схемой:

```dart
final userRepositoryProvider = Provider<UserRepository>((ref) {
  return MattermostUserRepository(
    api: ref.watch(activeMattermostApiProvider),
    cacheDao: ref.watch(userProfileCacheDaoProvider),
    avatarCache: ref.watch(avatarCacheProvider),
  );
});

final postRepositoryProvider = Provider<PostRepository>((ref) {
  return MattermostPostRepository(
    api: ref.watch(activeMattermostApiProvider),
    users: ref.watch(userRepositoryProvider),
  );
});
```

Сам repository получает зависимости через constructor и не хранит `Ref`. Это
сохраняет тестируемость и не превращает Riverpod в service locator внутри
бизнес-кода.

Providers активного аккаунта зависят от data-owned session/account context.
При login/logout/server switch этот context атомарно заменяет/закрывает API
client и инвалидирует account-scoped repositories. Он не читает состояние
`AuthController`.

UI controllers используют только provider с публичным типом domain repository.
Можно экспортировать такие handles одним `repository_providers.dart`, но нельзя
экспортировать через него raw API, DTO, DAO или concrete repository.

### 5.5. Domain models и UI state

Domain содержит факты и правила Mattermost:

- `UserSummary`, `UserProfile`, `Presence`;
- `Team`, `Channel`, `ChannelCategory`, `ChannelNavigation`;
- `Post`, `PostAuthor`/`UserSummary`, `Reaction`, `Attachment`, `EmojiRef`;
- `Thread`, `FollowedThread`;
- чистые display-name, merge, ordering и optimistic projection policies.

UI содержит:

- `isInitialLoading`, `isRefreshing`, `isLoadingMore`;
- retry/non-blocking errors;
- выбранный destination/channel;
- composer draft, focus, scroll anchor, expanded/collapsed UI;
- presentation-only grouping, localized labels и formatted timestamps.

Pagination cursor может присутствовать в domain-typed repository result как
opaque value, но UI не интерпретирует его и не строит Mattermost API query.

## 6. Целевые потоки данных

### Авторизация

```text
AuthController
  -> AuthRepository.login/restore/logout
      -> public/raw Mattermost API
      -> SSO browser service
      -> secure credential store
      -> active account context
  <- AuthSession / typed failure
```

UI переводит typed failure в локализованное сообщение. Token никогда не
возвращается в UI-state.

### Профили и кеш

```text
Posts/Channels/Users controller
  -> UserRepository
      -> profile cache DAO (account-scoped, TTL)
      -> raw users API for missing/expired entries
      -> user mapper
  <- UserSummary/UserProfile
```

Fresh profile является явной repository operation/freshness option, а не
обходом скрытого API decorator.

### Лента постов

```text
ChannelPostsController
  -> PostRepository.loadChannelPage
      -> raw posts API
      -> UserRepository batch author resolution
      -> PostMapper
  <- Page<Post> + opaque cursor + completeness
  -> domain PostCollection.merge
  -> ChannelPostsViewState
```

Controller не вызывает users API и не знает, почему автор пришёл из Drift или
сети. Ошибка pagination меняет только UI-флаги; уже показанный список остаётся.

### Realtime

```text
WebSocketGateway event
  -> repository/data event mapper
  -> domain reconciliation policy
  -> subscribed screen controller state
```

Sequence gaps и resync принадлежат data/repository policy. Auto-disposed screen
state остаётся network-first и не начинает сохраняться в Drift.

## 7. План миграции

Миграция должна быть инкрементальной. На каждом этапе приложение остаётся
собираемым, а поведение защищается существующими и новыми focused tests.

### Этап 0. Зафиксировать границы и baseline

1. Принять этот документ как ADR/target.
2. Зафиксировать текущие auth, cache, sidebar, posts, thread, reaction и
   attachment tests как regression baseline.
3. Добавить автоматическую проверку импортов:
   - domain не импортирует data/UI/framework packages;
   - UI не импортирует `data/api`, `data/database`, `data/cache`, DTO и concrete
     repositories;
   - data не импортирует UI;
   - `ui/core` не импортирует domain/data.
4. Не запрещать старые `features/*` сразу: вести временный allowlist, который
   только уменьшается.

### Этап 1. Создать каркас новых слоёв

1. Создать `data`, `domain`, `ui` без изменения поведения.
2. Перенести generic design tokens и действительно базовые widgets из
   `core/ui` в `ui/core`.
3. Перенести `app` bootstrap/router отдельно от UI shell.
4. Добавить barrel files только для небольших стабильных публичных API; не
   скрывать ими циклические зависимости.

### Этап 2. Перенести raw data infrastructure

1. Переместить `core/api` в `data/api` и разделить монолитный DTO-файл по
   сущностям.
2. Переместить Drift, cache, secure storage, platform SSO/file saver и logging
   adapters в соответствующие `data/*` папки.
3. Оставить временные forwarding exports для старых импортов.
4. Не менять endpoint semantics, timeouts, redaction и schema migration history.
5. После перемещения прогнать DTO/API/database migration tests.

### Этап 3. Сформировать общий domain

1. Перенести `AuthSession`, user, channel, post, thread, emoji и attachment
   models в `domain/models`.
2. Переименовать экранно-специфичные общие типы: например, `ChannelPost` в
   `Post`, если модель действительно используется вне channel feed.
3. Разделить domain data и UI-state: убрать refresh/error flags из
   `ChannelSidebarSnapshot`.
4. Перенести display-name, ordering, page merge, reply summary и reaction
   projection в чистые domain policies с unit tests.
5. На переходный период использовать deprecated type aliases/exports; не
   поддерживать две независимые копии одной модели.

### Этап 4. Перестроить session и provider graph

1. Создать data-owned active account context.
2. Перенести provider wiring инфраструктуры и repositories из
   `app/di/app_providers.dart` в `data/providers`.
3. Убрать зависимость active API provider от `AuthController`.
4. Проверить атомарное закрытие transport и provider invalidation при login,
   logout, restore и смене server/account.
5. Оставить UI только domain `AuthSession` без token/API client.

### Этап 5. Мигрировать `AuthRepository`

1. Объединить server discovery, SSO browser hand-off, token validation, secure
   persistence и active client lifecycle за единым domain-контрактом.
2. Сохранить различие invalid credentials и transient failure.
3. Упростить `AuthController` до UI state machine, вызывающей repository
   commands.
4. Перенести auth widgets в `ui/auth` и удалить их feature-копии.

Auth идёт первым, потому что все authenticated repositories зависят от active
account context.

### Этап 6. Мигрировать `UserRepository` и кеш

1. Объединить profile, mention и avatar public contracts.
2. Перенести TTL/account-scope policy из `CachedUserProfileApi` в
   `MattermostUserRepository`.
3. Оставить cache DAO и avatar byte cache внутренними data services.
4. Удалить `CachedUserProfileApi` после перевода всех consumers.
5. Проверить batch behavior, stale failure, username case-insensitive lookup,
   fresh profile bypass и avatar cache keys.

UserRepository мигрирует раньше каналов/постов/тредов, потому что они используют
author/dialog enrichment.

### Этап 7. Мигрировать каналы и shell

1. Объединить sidebar и direct-channel operations в `ChannelRepository`.
2. Инжектировать `UserRepository` в implementation через provider graph.
3. Возвращать semantic category kind вместо английского fallback label.
4. Создать `ChannelSidebarViewState` с refresh/error flags.
5. Перенести selection/navigation orchestration в `ui/shell` и
   `ui/channels`; удалить глобальную `openDirectMessage(WidgetRef, ...)`.

### Этап 8. Мигрировать посты и общие message surfaces

1. Объединить page load, create post/reply и reaction operations в
   `PostRepository`.
2. Перевести mapper на root domain models и `UserRepository`.
3. Заменить controller-local merge/reply/reaction правила на domain policies.
4. Перенести composer, Markdown, author/avatar, reactions и attachment surfaces
   в `ui/messages`.
5. Сохранить volatile autoDispose state, stable pending post ID и rollback
   semantics.

### Этап 9. Мигрировать треды

1. Объединить detail/followed/mark-read в `ThreadRepository`.
2. Использовать общие `Post`, user resolution и reconciliation policies.
3. Оставить unread divider, scroll destination и non-blocking feedback в UI.
4. Проверить cursor loop protection, deleted placeholders, read timestamp и
   totals after local mark-read.

### Этап 10. Мигрировать emoji и attachments

1. Перевести repositories на root domain types.
2. Сохранить metadata-first emoji lookup, in-flight coalescing и bounded caches.
3. Сохранить авторизованную загрузку файлов и platform save boundary.
4. Убедиться, что `ui/messages` получает bytes/content domain results, но не API
   или credentials.

### Этап 11. Удалить compatibility layer

1. Удалить `features/*/{data,domain}` и старые forwarding exports.
2. Оставить UI feature grouping только под `ui/*`.
3. Удалить монолитный `app/di/app_providers.dart` либо оставить в `app` только
   root ProviderScope overrides/bootstrap без repository construction.
4. Обновить `docs/ARCHITECTURE.md` после фактического завершения миграции.
5. Сделать import-boundary checks обязательными в CI.

## 8. Сложности и риски миграции

### 8.1. Риск «переложить файлы, сохранив связанность»

Если просто переместить все feature domain models в одну папку, но оставить
`MessageSender`, `ReactionRepository`, `ChannelPostRepository` и controller
reconciliation без изменений, проблема сменит пути импортов, но не архитектуру.
Критерий этапа — изменение владельца поведения и публичных контрактов, а не
число перемещённых файлов.

### 8.2. Слишком крупные repositories

Буквальное применение «одна сущность — один repository» может создать god
objects. Сдерживающее правило: один публичный contract на aggregate, несколько
private services/DAO/mappers внутри implementation, use case только для
действительно cross-repository business workflow.

### 8.3. Provider cycles

`PostRepository` и `ChannelRepository` хотят использовать `UserRepository`, а
active account и auth создают API для всех трёх. Нельзя допустить обратную
зависимость `UserRepository -> PostRepository/ChannelRepository` или создание
active API из UI auth provider. Provider graph нужно зафиксировать тестом/схемой
до миграции consumers.

### 8.4. Lifecycle активного API

При переносе session ownership легко оставить старый Dio client живым,
пересоздать repository со старым account scope или ненадолго смешать session и
API разных аккаунтов. Замена active context должна быть атомарной, а dispose —
явно протестированным.

### 8.5. Изменение семантики user cache

Удаление `CachedUserProfileApi` затрагивает не только profile card, но и author,
mention, DM и thread participant enrichment. Особенно важны:

- batch вместо N+1;
- TTL и запрет stale fallback после refresh failure;
- account/server scope;
- fresh card bypass;
- username case-insensitive index;
- отсутствие avatar bytes в Drift.

### 8.6. Pagination и reconciliation

Post cursor берётся из raw order, включая replies, тогда как UI показывает
только roots. Thread cursor использует одновременно ID и create timestamp.
Followed thread cursor — root ID. Унификация `Page<T>` не должна стереть эти
различия: cursor opaque для UI, но стратегия остаётся repository-specific.

### 8.7. Optimistic update и будущий WebSocket

После появления realtime один post/reaction может прийти из REST response,
optimistic projection и WebSocket event. Нужны idempotency и единая domain
reconciliation policy. Иначе перенос текущей логики из двух controllers только
закрепит расхождения.

### 8.8. Граница UI-логики

Не вся логика controller-а должна уйти из UI. Loading flags, сохранение полезных
данных при refresh, draft/focus/scroll и локализованные ошибки остаются в UI.
DTO mapping, cache freshness, endpoint selection, cursor construction и retry/
rate-limit policy остаются в data. Чистые ordering/merge/reaction rules находятся
в domain. Эту границу следует проверять code review, а не только путями файлов.

### 8.9. Большой объём механических импортов

Одновременный big-bang затронет практически все source и tests. Forwarding
exports и миграция по aggregate уменьшают риск, но временные aliases должны иметь
дату удаления/allowlist; иначе переходный слой станет постоянным.

### 8.10. Generated code и Drift history

Перемещение Drift-файлов меняет import/part paths, но не должно переписывать
released migrations. Generated `*.g.dart` нельзя редактировать вручную. Если
schema не меняется, migration behavior всё равно нужно проверить с базами старых
версий.

### 8.11. Производительность и rebuild scope

Глобальный `UserRepository` не означает глобальный UI-state. Экранные списки
остаются autoDispose, Riverpod watchers используют `select`, а immutable domain
модели не должны приводить к пересозданию всей ленты при загрузке одного avatar.

### 8.12. Локализация

При переносе mapper-ов обнаружатся английские fallback labels в data и строки в
widgets. Domain должен возвращать semantic kind, а UI — локализовать. Это может
увеличить diff, поэтому локализацию нужно мигрировать вместе с соответствующим
UI-сценарием, не меняя server-provided display names.

## 9. Критерии завершения

Миграция завершена, когда одновременно выполняются условия:

1. Общие domain models не находятся внутри UI-feature.
2. Нет импортов между бывшими `features/*/domain` или `features/*/data`, потому
   что этих слоёв внутри feature больше нет.
3. UI не импортирует raw API, DTO, Dio, DAO, cache/storage implementations или
   concrete repositories.
4. Raw `MattermostApi` не содержит cache/domain/UI behavior.
5. User cache реализован внутри `UserRepository`, а `CachedUserProfileApi`
   удалён.
6. Active API/session context не зависит от `AuthController`.
7. На aggregate есть один публичный repository contract; operation-specific
   repositories удалены.
8. UI-specific flags находятся в view-state, а общие merge/reconciliation rules
   протестированы в domain.
9. Network-first/autoDispose, pagination, auth security, cache scoping,
   optimistic rollback и thread read semantics не изменились.
10. `dart format`, `flutter analyze`, focused tests и полный `flutter test`
    проходят без новых предупреждений и ошибок.
