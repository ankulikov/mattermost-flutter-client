# Channel posts

The posts slice owns the domain representation and presentation of channel
history. During the visual prototype phase, `InMemoryChannelPostRepository`
generates 120 deterministic channel-specific messages after an artificial delay,
including consecutive runs by the same author for grouped-message presentation.
The presentation layer depends only on `ChannelPostRepository`, so the mock can
later be replaced by an offline-first Drift/API implementation without changing
the widgets.

Message text is currently rendered as plain text. Reactions are represented by
an emoji and aggregate count; realtime updates, pagination, Markdown, files,
threads, and mutation outbox behavior are intentionally deferred.
