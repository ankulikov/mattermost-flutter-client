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
Widgets / adaptive layouts
        │ watch / commands
        ▼
Riverpod controllers
        │ volatile page/thread state
        ▼
Domain repositories
        ▼
MattermostApi
        ▼
Mattermost API v4

AppDatabase (Drift) ── reserved for future durable feature data
```

Presentation не вызывает HTTP, WebSocket, DAO или secure storage напрямую.
Контроллер обращается к domain-контракту репозитория; data-реализация получает
DTO через `MattermostApi` и явно преобразует их в domain entities.

## Модули и зависимости

Продуктовый код организован вертикальными feature slices:

```text
features/<feature>/
  domain/        # entities and repository contracts
  data/          # API implementations and DTO mappers
  presentation/  # Riverpod state and widgets
```

Зависимости направлены внутрь:

```text
presentation -> domain <- data -> core infrastructure
```

Domain не импортирует Flutter, Riverpod, Dio, Drift или API DTO. Все REST-вызовы
проходят через `MattermostApi`; Dio создается только в core API wiring.

## Посты и пагинация

- Последняя страница загружается с `page=0&per_page=60`.
- Более старая история загружается через `before=<raw_post_id>`.
- Курсор берется из последнего id в сыром `PostList.order`, а не из последнего
  видимого root-поста. Поэтому страницы, содержащие только replies, не приводят
  к пропускам или циклам пагинации.
- Ответ канала фильтруется до root-постов после маппинга. Replies показываются в
  отдельном треде.
- Контроллер объединяет страницы по `post.id` и сортирует по `create_at`, затем
  по id. Состояние освобождается при закрытии канала.

## Треды

Открытие треда вызывает `GET /posts/{post_id}/thread`. Репозиторий использует
`fromPost` и `fromCreateAt`, ограничивает одну загрузку 20 страницами и возвращает
root с replies одним domain-снимком. Replies сортируются по `create_at`, затем по
id; редактирование поста не меняет порядок. Закрытие панели освобождает снимок.

## Сайдбар

Сайдбар при входе загружает первую команду пользователя, ее каналы и категории.
Имена direct/group диалогов дополняются через users API. Результат хранится в
контроллере; ручной refresh сохраняет текущий снимок на экране до успешного
ответа и показывает неблокирующую ошибку при неудаче.

## База данных

`AppDatabase` намеренно не содержит таблиц текущих features. Schema version 7
удаляет прежние 11 таблиц сайдбара, постов, реакций, порядка и sync metadata.
Сам Drift, platform-specific подключения и provider сохранены для будущего
персистентного кэша пользователей.

Новые таблицы добавляются только вместе с явным владельцем данных, политикой
актуальности и причиной, по которой состояние должно переживать процесс.

## Адаптивность, безопасность и асинхронность

- Макет выбирается по доступной ширине через constraints, а не по платформе.
- Все user-facing строки локализуются вне widgets; поддерживаются keyboard,
  semantics, scalable text и light/dark themes.
- Токены хранятся только в secure storage и не попадают в Drift или логи.
- Большой JSON parsing переносится с UI isolate; запросы и пагинация имеют
  ограниченную конкуренцию и обязаны учитывать rate limits.
- Каждый Future await-ится либо явно передается в централизованную обработку.

## Проверка изменений

Изменения форматируются, проверяются `flutter analyze` и focused tests. Для UI
проверяются compact/expanded widths и большой text scale. При добавлении будущих
Drift-таблиц обязательны code generation, migration и migration test.
