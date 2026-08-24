# Local storage

Drift is the authoritative application data source. Add tables and DAOs here by
feature (`accounts`, `users`, `teams`, `channels`, `posts`, `files`, `preferences`,
`outbox`, `sync_cursors`). Platform-specific database opening belongs in this
directory and must use a background isolate on native platforms and Drift WASM
with a worker on Web.

Authentication tokens are not database columns: keep them in
`flutter_secure_storage` and reference them by account id.

